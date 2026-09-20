#!/usr/bin/env python3
"""Generate .audit/<id>/pack.md for one surface -- the facts a design session needs
so it can read one page instead of the whole surface.

Deterministic on purpose. No model writes any part of this file, so nothing in it
can be invented and later trusted. Regenerate rather than maintain.

  python3 tools/audit/pack.py modules/ii/clipboardToast
  python3 tools/audit/pack.py modules/settings/BarConfig.qml --id settings-bar
  python3 tools/audit/pack.py modules/common/widgets --only '^Ripple' --id cw-buttons
"""
import argparse, importlib.util, os, pathlib, re, sys
from collections import Counter, defaultdict

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
SHELL = ROOT / "dots/.config/quickshell/ii"
WIDGETS = SHELL / "modules/common/widgets"

# Raw primitives that usually mean a shared widget was rebuilt by hand.
REBUILD_HINT = {
    "MouseArea": "RippleButton / StateLayer",
    "Text": "StyledText",
    "ListView": "StyledListView",
    "TextField": "StyledTextField",
    "ScrollView": "StyledScrollView",
    "Slider": "StyledSlider",
    "Button": "RippleButton",
}

def load_config_parser():
    spec = importlib.util.spec_from_file_location(
        "ccp", ROOT / "tools/p3-widget-port/check-config-paths.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

def qml_files(target, only=None):
    if target.is_file():
        return [target]
    files = sorted(p for p in target.rglob("*") if p.suffix in (".qml", ".js"))
    if only:
        # A tranche too big for one session is packed per family instead. Match on the
        # path relative to the target so `--only 'transitions/|^Styled'` reads naturally.
        rx = re.compile(only)
        files = [f for f in files if rx.search(str(f.relative_to(target)))]
    return files

def root_type(src):
    for line in src.split("\n"):
        m = re.match(r"^([A-Z]\w*)\s*\{", line)
        if m:
            return m.group(1)
    return "-"

# DESIGN.md 8: effects are a budget, and the expensive mistake is one inside a
# delegate that repeats. ponytail: brace counting, not a QML parser -- it over-reports
# a nested close on one line rather than missing an effect.
EFFECTS = re.compile(
    r"\b(layer\.enabled|MultiEffect|OpacityMask|ShaderEffectSource|ShaderEffect|GaussianBlur"
    r"|StyledDropShadow|StyledRectangularShadow|StyledBlurEffect|DropShadow|ColorOverlay"
    r"|Colorizer|ShapeCanvas|Canvas)\b")
REPEATED = re.compile(r"\b(delegate\s*:|Repeater\s*\{|Instantiator\s*\{)")

def effect_census(src):
    """(line, what, repeated?) for every effect and every sub-100ms Timer."""
    out, opens, depth = [], [], 0
    for i, ln in enumerate(src.split("\n"), 1):
        repeats = bool(opens)
        for m in EFFECTS.finditer(ln):
            out.append((i, m.group(1), repeats))
        t = re.search(r"\binterval\s*:\s*(\d+)\b", ln)
        if t and 0 < int(t.group(1)) < 100:
            out.append((i, f"Timer {t.group(1)}ms", repeats))
        if REPEATED.search(ln):
            opens.append(depth)
        depth += ln.count("{") - ln.count("}")
        while opens and depth <= opens[-1]:
            opens.pop()
    return out

def declarations(src):
    props = re.findall(r"^\s*(?:readonly\s+)?property\s+(?:list<)?(\w+)>?\s+(\w+)", src, re.M)
    signals = re.findall(r"^\s*signal\s+(\w+)", src, re.M)
    funcs = re.findall(r"^\s*function\s+(\w+)", src, re.M)
    return props, signals, funcs

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("surface", help="path under the shell dir")
    ap.add_argument("--id", help="surface id (default: derived from path)")
    ap.add_argument("--only", help="regex on the path relative to the surface dir; packs "
                                   "one family of a tranche too big for one session")
    args = ap.parse_args()

    target = SHELL / args.surface
    if not target.exists():
        sys.exit(f"no such surface: {target}")
    sid = args.id or re.sub(r"[^a-zA-Z0-9]+", "-", args.surface.replace("modules/", "")).strip("-").removesuffix("-qml")

    files = qml_files(target, args.only)
    if not files:
        sys.exit(f"no qml under {target}")

    ccp = load_config_parser()
    cfg = ccp.parse_tree(str(SHELL / "modules/common/Config.qml"), ccp.CONFIG_ROOT_RE)

    shared = {p.stem for p in WIDGETS.rglob("*.qml")}
    local = {f.stem for f in files if f.suffix == ".qml" and f.stem[:1].isupper()}

    rows, decls, conf, used, prims, ipc = [], {}, defaultdict(set), Counter(), Counter(), []
    effects = []
    total = 0
    for f in files:
        src = f.read_text(errors="replace")
        n = src.count("\n") + 1
        total += n
        rel = f.relative_to(target) if target.is_dir() else f.name
        rows.append((str(rel), n, root_type(src)))
        decls[str(rel)] = declarations(src)
        for line, what, repeated in effect_census(src):
            effects.append((str(rel), line, what, repeated))
        for m in re.finditer(r"Config\.options\.([A-Za-z0-9_.]+)", src):
            conf[m.group(1).rstrip(".")].add(str(rel))
        for m in re.finditer(r"\b([A-Z][A-Za-z0-9_]*)\s*\{", src):
            t = m.group(1)
            (prims if t in REBUILD_HINT else used)[t] += 1
        if "IpcHandler" in src:
            ipc += [(str(rel), t) for t in re.findall(r'target:\s*"(\w+)"', src)]
            ipc += [(str(rel), "fn " + fn) for fn in re.findall(r"^\s*function\s+(\w+)", src, re.M)
                    if "IpcHandler" in src.split(f"function {fn}")[0][-400:]]

    # who reaches a type defined in it, by instantiation (`Type {`) or by url
    # (`Qt.resolvedUrl("widgets/Type.qml")`) — the settings sub-pages use only the latter
    callers = defaultdict(set)
    if local:
        # longest name first, and the url's path prefix has to end at a separator, so
        # `DesktopBluetoothBatteryConfig.qml` is not also read as a use of `BatteryConfig`
        names = "|".join(sorted(local, key=len, reverse=True))
        pat = re.compile(rf"\b({names})\s*[{{.]|[\"'](?:[\w./]*/)?({names})\.qml[\"']")
        for p in SHELL.rglob("*.qml"):
            if "user_widgets" in p.parts:
                continue
            for a, b in set(pat.findall(p.read_text(errors="replace"))):
                if p.stem != (a or b):  # a file naming itself is not a caller
                    callers[a or b].add(str(p.relative_to(SHELL)))

    o = [f"# {sid} — pack", "",
         f"`{args.surface}` · {len(files)} files · {total} lines · generated by `tools/audit/pack.py`",
         "", "## Files", "", "| file | lines | root |", "|---|---:|---|"]
    o += [f"| `{r}` | {n} | {t} |" for r, n, t in sorted(rows, key=lambda x: -x[1])]

    o += ["", "## Declared API", ""]
    for r, (props, signals, funcs) in sorted(decls.items()):
        if not (props or signals or funcs):
            continue
        o.append(f"**`{r}`**")
        if props:
            o.append("- props: " + ", ".join(f"`{n}`*({t})*" for t, n in props))
        if signals:
            o.append("- signals: " + ", ".join(f"`{s}`" for s in signals))
        if funcs:
            o.append("- functions: " + ", ".join(f"`{f}`" for f in funcs))
        o.append("")

    o += ["## Config options read", ""]
    if not conf:
        o.append("_none_")
    for path in sorted(conf):
        ok = ccp.resolve(path.split("."), cfg)
        flag = "" if ok else "  **MISSING — reads as undefined, silently**"
        o.append(f"- `Config.options.{path}`{flag}  ·  {', '.join(sorted(conf[path])[:3])}")

    o += ["", "## Widget vocabulary", "",
          "Shared widgets already used (keep using these):", ""]
    sw = sorted((t, c) for t, c in used.items() if t in shared)
    o += ([f"- `{t}` ×{c}" for t, c in sw] or ["_none — suspicious for a UI surface_"])
    if prims:
        o += ["", "Raw primitives — each is a possible rebuild of a shared widget:", ""]
        o += [f"- `{t}` ×{c} → consider `{REBUILD_HINT[t]}`" for t, c in prims.most_common()]
    dup = sorted(local & shared)
    if dup:
        o += ["", f"**Name collision with a shared widget:** {', '.join('`'+d+'`' for d in dup)}"]

    o += ["", "## Effect budget", "",
          "One layer or effect per widget, never inside something that repeats (8). "
          "A sub-100ms Timer is JS every frame or faster.", ""]
    if not effects:
        o.append("_no effects and no fast timers — nothing to spend here_")
    else:
        o += ["| file | line | what | repeated |", "|---|---:|---|---|"]
        o += [f"| `{f}` | {n} | `{w}` | {'**yes**' if r else ''} |"
              for f, n, w, r in sorted(effects, key=lambda e: (not e[3], e[0], e[1]))]

    o += ["", "## Used by", ""]
    if not callers:
        o.append("_nothing outside this surface instantiates its types — self-contained_")
    for t in sorted(callers):
        o.append(f"- `{t}` ← {', '.join(sorted(callers[t])[:6])}")
    unused = sorted(local - set(callers))
    if unused:
        o += ["", f"**No caller anywhere — {len(unused)} of {len(local)}:** "
                  + ", ".join("`" + u + "`" for u in unused),
              "", "A caller inside this surface counts too, so a name here is reached by "
                  "nothing at all. For whether a *chain* of them is reached from outside — "
                  "a page loaded only by another page nobody loads — run "
                  "`tools/audit/reachable.py <dir>`."]

    o += ["", "## How to open it", ""]
    o += ([f"- `{r}`: {t}" for r, t in ipc] or
          ["_no IpcHandler here — record the keybind or trigger in QUEUE.md_"])

    out = ROOT / ".audit" / sid / "pack.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(o) + "\n")
    print(f"{out.relative_to(ROOT)}  ({len(o)} lines, from {total} lines of QML)")

if __name__ == "__main__":
    main()
