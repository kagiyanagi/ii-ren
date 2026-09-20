#!/usr/bin/env python3
"""Assert the text primitives' contract, which only shows up at runtime.

`StyledText` has 471 callers and `MaterialSymbol` 398, so both of these are
invisible when broken and wrong 400 times over:

  * A label that outgrows its cell must truncate, not draw past it
    (DESIGN.md 10.17). That is `elide: Text.ElideRight` on the shared root --
    measured to leave wrapped and unconstrained text alone.
  * A Material Symbol must NOT inherit it. One glyph elided measures 0 wide and
    disappears -- not an ellipsis, nothing -- so a squeezed row loses its icon.
  * The swap animation moves a Translate. Assigning x/y to an item its parent
    positions is overridden every layout pass (2.9), so an anchored or
    Layout-placed caller would silently get a fade with no travel.

It also fails when a *new* Text-rooted primitive lands in the library without
saying which side of the elide contract it is on -- that widget would be the
next one to ship 10.17 by accident.

  python3 tools/check-text-primitives.py
"""
import pathlib, re, sys

WIDGETS = pathlib.Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/modules/common/widgets"
fails = []


def check(cond, msg):
    if not cond:
        fails.append(msg)


def src(name):
    return (WIDGETS / f"{name}.qml").read_text()


styled, symbol = src("StyledText"), src("MaterialSymbol")

check(re.search(r"^\s*elide:\s*Text\.ElideRight\s*$", styled, re.M),
      "StyledText must default to elide: Text.ElideRight (DESIGN.md 10.17)")
check(re.search(r"^\s*elide:\s*Text\.ElideNone\s*$", symbol, re.M),
      "MaterialSymbol must set elide: Text.ElideNone -- an elided glyph renders as nothing")

# The swap: a Translate, on effects specs, in both directions.
check("transform: Translate" in styled,
      "StyledText's swap must move a Translate, not x/y (DESIGN.md 2.9)")
check(not re.search(r'property:\s*"[xy]"[^}]*?\n\s*to:\s*textAnimationBehavior', styled),
      "StyledText's swap must not animate its own x/y back to a construction-time value")
for spec in ("elementMoveExit", "elementMoveFast"):
    for field in ("duration", "bezierCurve"):
        check(f"Appearance.animation.{spec}.{field}" in styled,
              f"StyledText's swap must take its {field} from Appearance.animation.{spec}")
check(not re.search(r"easing\.type:\s*Easing\.(?!BezierSpline)", styled),
      "StyledText must not hand-fit an easing curve -- Appearance.animationCurves.* only")

# Any other Text-rooted primitive has to pick a side.
for f in sorted(WIDGETS.glob("*.qml")):
    if f.stem in ("StyledText", "MaterialSymbol"):
        continue
    body = f.read_text()
    if re.match(r"^(?:pragma[^\n]*\n|import[^\n]*\n|//[^\n]*\n|\s*\n)*Text\s*\{", body):
        check("elide:" in body,
              f"{f.stem} is rooted in Text and declares no elide -- say ElideRight or ElideNone")

for msg in fails:
    print(f"FAIL {msg}")
print(f"{'FAILED' if fails else 'ok'}: text primitives, {len(fails)} failure(s)")
sys.exit(1 if fails else 0)
