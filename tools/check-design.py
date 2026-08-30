#!/usr/bin/env python3
"""Check the shell's QML against .github/DESIGN.md.

Only the mechanically detectable rules live here -- literal numbers where a token
exists, animation types that do not match their property, the crash and
shadowing patterns. Judgement calls (is this the right transform origin, is this
spatial or effects, does the spacing read) still need a human or a read-through.

  python3 tools/check-design.py                 # full audit, informational
  python3 tools/check-design.py --diff          # only lines added vs HEAD, exits 1 on error
  python3 tools/check-design.py --diff main
  python3 tools/check-design.py --rule literal-duration    # every hit for one rule
  python3 tools/check-design.py -v              # every hit for every rule

Suppress a deliberate exception with `// design-ok: reason` on the line or the
line above. Numbers transcribed from AOSP are accepted when the comment says so.
"""
import argparse, pathlib, re, subprocess, sys
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parent.parent
QML_ROOT = ROOT / "dots/.config/quickshell/ii"
# Appearance.qml *is* the token source; shapes is a submodule.
SKIP = {"modules/common/Appearance.qml", "modules/common/AnimSpec.qml",
        "modules/common/Config.qml"}  # tokens source; anim spec; config schema
SKIP_DIRS = ("modules/common/widgets/shapes/",)

# A literal is fine when the comment says where it came from.
CITED = re.compile(
    r"design-ok|AOSP|Compose|Launcher3|ArrowPopup|FastBitmapDrawable|RippleAnimation"
    r"|MotionTokens|PathInterpolator|StateTokens|ShapeTokens|Material|\bM3\b",
    re.I,
)
COLORISH = re.compile(r"^(col[A-Z]|color$|.*Color$|.*Colour$)")
NUMERIC = re.compile(
    r"^(opacity|scale|rotation|x|y|z|width|height|radius|spacing|padding"
    r"|implicit\w+|\w*Margin|\w*Radius|\w*Scale|\w*Size|value|position|angle)$"
)
# 4dp grid, plus the 6 and 10 this codebase already uses everywhere.
ON_GRID = {0, 2, 4, 6, 8, 10} | {n for n in range(12, 201, 4)}


def cited(lines, i):
    return any(CITED.search(lines[j]) for j in range(max(0, i - 2), i + 1))


def rule_literal_duration(lines):
    for i, ln in enumerate(lines):
        m = re.search(r"\bduration:\s*(\d+)\b", ln)
        if m and int(m.group(1)) > 0 and not cited(lines, i):
            yield i, f"duration: {m.group(1)} -- use Appearance.animation.*.duration"


def rule_inline_curve(lines):
    for i, ln in enumerate(lines):
        if re.search(r"bezierCurve:\s*\[", ln) and not cited(lines, i):
            yield i, "inline bezier -- use Appearance.animationCurves.*"


def rule_hex_color(lines):
    for i, ln in enumerate(lines):
        if "??" in ln or "//" in ln.split('"')[0]:
            continue  # defensive fallback, or a comment
        if re.search(r'"#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6,8})"', ln) and not cited(lines, i):
            yield i, "hex literal -- use Appearance.colors.*"


def rule_literal_radius(lines):
    for i, ln in enumerate(lines):
        m = re.search(r"\b(\w*[Rr]adius):\s*(\d+)\b", ln)
        if not m or "Appearance" in ln or cited(lines, i):
            continue
        if int(m.group(2)) == 0 or "blur" in m.group(1).lower():
            continue
        yield i, f"{m.group(1)}: {m.group(2)} -- use Appearance.rounding.*"


def rule_literal_font_size(lines):
    for i, ln in enumerate(lines):
        m = re.search(r"\bpixelSize:\s*(\d+)\b", ln)
        if m and "Appearance" not in ln and not cited(lines, i):
            yield i, f"pixelSize: {m.group(1)} -- use Appearance.font.pixelSize.*"


def behavior_block(lines, i):
    """Text of the Behavior block starting on line i, brace-matched.

    A fixed lookahead swallows the *next* sibling Behavior and reports its
    animation type against this one's property.
    """
    depth, out = 0, []
    for j in range(i, min(len(lines), i + 40)):
        ln = lines[j]
        out.append(ln)
        depth += ln.count("{") - ln.count("}")
        if depth <= 0 and (j > i or ("{" in ln and "}" in ln)):
            break
    return "".join(out)


def rule_anim_type_mismatch(lines):
    """A Behavior whose animation type does not match the property type snaps."""
    for i, ln in enumerate(lines):
        m = re.search(r"Behavior on (\w+)", ln)
        if not m:
            continue
        prop, block = m.group(1), behavior_block(lines, i)
        if COLORISH.match(prop) and ("numberAnimation" in block or "NumberAnimation" in block):
            yield i, f"Behavior on {prop} (a colour) using a NumberAnimation -- it will snap"
        elif NUMERIC.match(prop) and ("colorAnimation" in block or "ColorAnimation" in block):
            yield i, f"Behavior on {prop} (a real) using a ColorAnimation -- it will snap"


def rule_spring_animation(lines):
    for i, ln in enumerate(lines):
        if "SpringAnimation" in ln and not ln.lstrip().startswith("//"):
            yield i, "SpringAnimation is not a Compose spring (see DESIGN.md 2.9)"


def rule_bare_text(lines):
    for i, ln in enumerate(lines):
        if re.search(r"(?<![\w.])Text\s*\{", ln) and not cited(lines, i):
            yield i, "bare Text -- use StyledText"


def rule_off_grid_spacing(lines):
    for i, ln in enumerate(lines):
        m = re.search(r"\b(spacing|padding|\w*[Mm]argins?):\s*(\d+)\b", ln)
        if not m or cited(lines, i):
            continue
        if int(m.group(2)) not in ON_GRID:
            yield i, f"{m.group(1)}: {m.group(2)} -- off the 4dp grid"


NON_ITEM_ROOTS = {"Singleton", "QtObject", "ListModel", "JsonObject", "JsonAdapter",
                  "Instantiator", "Process", "Timer", "Connections", "SystemClock"}
LOCAL_ROOTS = {}  # component name -> its own root type, filled by main()


def root_type(lines):
    for ln in lines:
        m = re.match(r"^([A-Z]\w*)\s*\{", ln)
        if m:
            return m.group(1)
    return ""


def is_visual(root, depth=0):
    """Follow a local component's root type until it lands somewhere known."""
    if root in NON_ITEM_ROOTS:
        return False
    if depth >= 5 or root not in LOCAL_ROOTS:
        return True  # a Qt/Quickshell type we cannot resolve -- assume visual
    return is_visual(LOCAL_ROOTS[root], depth + 1)


def rule_shadowed_property(lines):
    if not is_visual(root_type(lines)):
        return  # nothing to shadow -- Item's `state`/`focus` are not there
    for i, ln in enumerate(lines):
        m = re.search(r"^\s*(?:readonly\s+)?property\s+\w+\s+(state|focus)\b", ln)
        if m:
            yield i, f"property named `{m.group(1)}` shadows Item's own -- rename (layerState / focused)"


def rule_async_connections(lines):
    """Async incubation plus a Connections target that is not a live QObject segfaults."""
    if not any("asynchronous: true" in ln for ln in lines):
        return
    for i, ln in enumerate(lines):
        m = re.search(r"^\s*target:\s*(.+?)\s*$", ln)
        if not m or i == 0 or "Connections" not in "".join(lines[max(0, i - 4) : i]):
            continue
        tgt = m.group(1)
        if "?? null" in tgt or tgt in ("null",) or tgt[0].isupper():
            continue  # guarded, or a singleton
        yield i, f"Connections target `{tgt}` under async incubation -- guard with `?? null`"


def rule_no_separator_bars(lines):
    """M3 Expressive separates sections via whitespace and layers, not divider bars."""
    for i, ln in enumerate(lines):
        if re.search(r"\bWindowDialogSeparator\b", ln) and not cited(lines, i):
            yield i, "WindowDialogSeparator -- avoid divider lines; use whitespace (12-16dp) and layer nesting (see DESIGN.md 5.5)"


RULES = [
    ("literal-duration", "warn", rule_literal_duration),
    ("inline-curve", "warn", rule_inline_curve),
    ("hex-color", "warn", rule_hex_color),
    ("literal-radius", "warn", rule_literal_radius),
    ("literal-font-size", "warn", rule_literal_font_size),
    ("off-grid-spacing", "warn", rule_off_grid_spacing),
    ("bare-text", "warn", rule_bare_text),
    ("anim-type-mismatch", "error", rule_anim_type_mismatch),
    ("spring-animation", "error", rule_spring_animation),
    ("shadowed-property", "error", rule_shadowed_property),
    ("async-connections", "warn", rule_async_connections),
    ("no-separator-bars", "warn", rule_no_separator_bars),
]


def qml_files():
    for p in sorted(QML_ROOT.rglob("*.qml")):
        rel = p.relative_to(QML_ROOT).as_posix()
        if rel in SKIP or rel.startswith(SKIP_DIRS):
            continue
        yield p, rel


def added_lines(ref):
    """{repo-relative path: {1-based line numbers added}} from a git diff."""
    out = subprocess.run(
        ["git", "-C", str(ROOT), "diff", "-U0", ref, "--", "*.qml"],
        capture_output=True, text=True,
    ).stdout
    added, path = defaultdict(set), None
    for ln in out.splitlines():
        if ln.startswith("+++ b/"):
            path = ln[6:]
        elif ln.startswith("@@") and path:
            m = re.search(r"\+(\d+)(?:,(\d+))?", ln)
            if m:
                start, count = int(m.group(1)), int(m.group(2) or 1)
                added[path].update(range(start, start + count))
    return added


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--diff", nargs="?", const="HEAD", metavar="REF",
                    help="only check lines added vs REF (default HEAD)")
    ap.add_argument("--rule", help="show every hit for one rule")
    ap.add_argument("-v", "--verbose", action="store_true", help="show every hit")
    args = ap.parse_args()

    touched = added_lines(args.diff) if args.diff else None
    findings = defaultdict(list)

    for p in QML_ROOT.rglob("*.qml"):
        LOCAL_ROOTS[p.stem] = root_type(p.read_text(errors="replace").splitlines())

    for path, rel in qml_files():
        repo_rel = path.relative_to(ROOT).as_posix()
        if touched is not None and repo_rel not in touched:
            continue
        lines = path.read_text(errors="replace").splitlines(keepends=True)
        suppressed = {
            i for i, ln in enumerate(lines)
            if "design-ok" in ln or (i and "design-ok" in lines[i - 1])
        }
        for rid, level, fn in RULES:
            if args.rule and rid != args.rule:
                continue
            for i, msg in fn(lines):
                if i in suppressed:
                    continue
                if touched is not None and (i + 1) not in touched[repo_rel]:
                    continue
                findings[rid].append((level, f"{repo_rel}:{i + 1}", msg))

    scope = f"lines added vs {args.diff}" if args.diff else "every QML file"
    print(f"check-design.py -- {scope}\n")
    errors = 0
    for rid, level, _ in RULES:
        if args.rule and rid != args.rule:
            continue
        hits = findings.get(rid, [])
        if level == "error":
            errors += len(hits)
        if not hits:
            print(f"  ok    {rid}")
            continue
        print(f"  {level.upper():5} {rid}: {len(hits)}")
        show = hits if (args.verbose or args.rule or level == "error") else hits[:3]
        for _, loc, msg in show:
            print(f"          {loc}: {msg}")
        if len(show) < len(hits):
            print(f"          ... {len(hits) - len(show)} more (--rule {rid})")

    total = sum(len(v) for v in findings.values())
    print(f"\n{total} finding(s), {errors} error(s).")
    if not args.diff and total:
        print("Full-repo run is informational -- it counts legacy debt too.")
        print("Use --diff to gate only what you just wrote.")
    print("Not checkable here: transform origin, spatial-vs-effects choice,")
    print("enter/exit pairing, layer nesting, effect-in-delegate. Read DESIGN.md.")
    return 1 if (args.diff and errors) else 0


if __name__ == "__main__":
    sys.exit(main())
