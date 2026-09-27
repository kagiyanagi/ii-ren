#!/usr/bin/env python3
"""Every `Appearance.<group>.<name>` in the tree names a property Appearance.qml declares.

A misspelt or wrong-group token is not an error in QML: it reads `undefined`, and the
log says "Unable to assign [undefined]" or "Cannot read property 'duration'" somewhere
far from the typo. `Appearance.colors.m3scrim` (it lives on `m3colors`) and
`Appearance.animation.fadeFast` (never existed) shipped in four files that way.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
APPEARANCE = (ROOT / "modules/common/Appearance.qml").read_text()


def group_members(src):
    """name -> set of property names declared one level inside `name: QtObject {` / `property X name: T {`."""
    groups, stack = {}, []
    for line in src.splitlines():
        s = line.strip()
        m = re.match(r"^(?:readonly )?(?:property [\w<>.]+ )?(\w+): \w+ \{", s)
        if m and not s.endswith("}"):
            stack.append(m.group(1))
            groups.setdefault(m.group(1), set())
            if len(stack) >= 2:
                groups.setdefault(stack[-2], set()).add(m.group(1))
            continue
        p = re.match(r"^(?:readonly )?property [\w<>.]+ (\w+)", s)
        owners = [g for g in stack if g is not None]
        if p and owners:
            groups[owners[-1]].add(p.group(1))
        # A value that opens braces of its own (`property var main: ({`) is not a
        # group, but its closing brace still pops: track it, or the group it sits
        # in is popped instead and every later member lands one level up.
        opened, closed = s.count("{"), s.count("}")
        if opened > closed:
            stack += [None] * (opened - closed)
        elif closed > opened:
            stack = stack[: max(0, len(stack) - (closed - opened))]
    return groups


GROUPS = group_members(APPEARANCE)
CHECKED = ("colors", "m3colors", "animation", "animationCurves", "rounding", "sizes")
for g in CHECKED + ("variableAxes", "pixelSize", "family"):
    assert GROUPS.get(g), f"Appearance.qml has no `{g}` group any more -- this check is stale"

# Vendored from ii-p3drovfx and rsynced over by tools/p3-widget-port, so a fix here is
# reverted by the next re-port. Named rather than
# skipped wholesale, so a new one in that tree still fails.
KNOWN = {
    "modules/ii/background/widgets/clock/concentric/ConcentricHourDisplay.qml: Appearance.font.family.display",
    "modules/ii/background/widgets/clock/concentric/ConcentricMinutePill.qml: Appearance.font.family.display",
}

bad = []
for f in sorted(ROOT.rglob("*.qml")):
    if "user_widgets" in f.parts:
        continue
    for n, line in enumerate(f.read_text(errors="ignore").splitlines(), 1):
        code = line.split("//")[0]
        if code.lstrip().startswith("*"):
            continue
        for g, name in re.findall(r"\bAppearance\.(\w+)\.(\w+)", code):
            if g in CHECKED and name not in GROUPS[g]:
                bad.append(f"{f.relative_to(ROOT)}:{n}: Appearance.{g}.{name} is not declared")
        # One level further for the font groups. `font.variableAxes.titleRounded`
        # never existed, and a QVariantMap assigned undefined only says so as a
        # runtime warning naming the widget, not the token.
        for g, name in re.findall(r"\bAppearance\.font\.(variableAxes|pixelSize|family)\.(\w+)", code):
            if name not in GROUPS[g] and f"{f.relative_to(ROOT)}: Appearance.font.{g}.{name}" not in KNOWN:
                bad.append(f"{f.relative_to(ROOT)}:{n}: Appearance.font.{g}.{name} is not declared")

assert not bad, "\n".join(bad)
print("check-appearance-refs: ok")
