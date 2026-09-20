#!/usr/bin/env python3
"""Assert DESIGN.md 9's dialog and tooltip recipes, which only show at runtime.

Everything here is silent when it breaks. `StyledToolTip` has 139 callers and
`WindowDialog` backs every confirm in the shell, so each of these is wrong
everywhere at once and none of it is visible to `check-design.py`:

  * A tooltip waits out the hover before it appears. With `delay: 0` the shell
    flashed a label at every pointer transit, which is what it did for years.
  * A tooltip fades and never scales. The box used to grow out of nothing --
    a size animated on an effects spec, reading as a scale.
  * The QQC2 style animates its own 300ms OutQuad/InQuad in *both* directions
    unless `enter`/`exit` are overridden, so "no exit animation" is not the
    failure here; "an exit nobody chose, as slow as the enter" is.
  * A popup tooltip unloads its window the moment the condition drops, which
    cuts the fade-out off mid-flight. Its loader has to outlive the condition.
  * A dialog's exit is not its enter: emphasizedDecel in, emphasizedAccel out,
    at about half the duration (2.5).
  * Padding never comes from a rounding token. Sharp mode zeroes the rounding
    scale, so a dialog that padded itself by its own radius lost every pixel of
    padding the moment someone turned sharp mode on.
  * 5.5 has no divider lines. The type is gone; the shape it had is not, so the
    rule follows the shape -- a hairline rectangle spanning a dialog.

  python3 tools/check-dialog-surfaces.py
"""
import pathlib, re, sys

WIDGETS = pathlib.Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/modules/common/widgets"
FAMILY = ["DialogListItem", "FullscreenPolkitWindow", "NoticeBox", "PopupToolTip",
          "SelectionDialog", "ShortcutBox", "StyledToolTip", "StyledToolTipContent",
          "WindowDialog", "WindowDialogButtonRow", "WindowDialogParagraph",
          "WindowDialogSectionHeader", "WindowDialogTitle"]
fails = []


def check(cond, msg):
    if not cond:
        fails.append(msg)


def src(name):
    return (WIDGETS / f"{name}.qml").read_text()


tip, content, popup, dialog = (src(n) for n in
                               ("StyledToolTip", "StyledToolTipContent", "PopupToolTip", "WindowDialog"))

# -- Tooltips: colTooltip, ~500ms delay, fade only, no scale (DESIGN.md 9) ----

for name, body in (("StyledToolTip", tip), ("PopupToolTip", popup)):
    m = re.search(r"^\s*(?:property\s+int\s+)?delay:\s*(\d+)\s*$", body, re.M)
    check(m and int(m.group(1)) >= 500,
          f"{name} must wait ~500ms before it appears (DESIGN.md 9); found {m.group(1) if m else 'no delay'}")

check("colTooltip" in content and "colOnTooltip" in content,
      "StyledToolTipContent must paint colTooltip/colOnTooltip, not a layer colour")

# Fade only. A size or scale animation on the box is the grow-out-of-nothing bug.
for name, body in (("StyledToolTip", tip), ("StyledToolTipContent", content)):
    bad = re.findall(r"Behavior on (implicitWidth|implicitHeight|width|height|scale)\b", body)
    check(not bad, f"{name} animates {bad} -- a tooltip fades and never scales (DESIGN.md 9)")

# Both directions, from named specs, and the exit is the shorter one.
for kind, spec in (("enter", "elementMoveFast"), ("exit", "elementMoveExit")):
    block = re.search(rf"^\s*{kind}:\s*Transition\s*\{{(.+?)^\s*\}}", tip, re.M | re.S)
    check(block, f"StyledToolTip must override the style's {kind} transition -- it is 300ms OutQuad by default")
    if block:
        check(f"Appearance.animation.{spec}.duration" in block.group(1),
              f"StyledToolTip's {kind} must take its duration from Appearance.animation.{spec}")
        check('property: "opacity"' in block.group(1),
              f"StyledToolTip's {kind} must animate opacity only (DESIGN.md 9)")

# The popup window has to outlive the condition or the fade-out never renders.
m = re.search(r"^\s*active:\s*(.+)$", popup, re.M)
check(m and "contentOpacity" in m.group(1),
      "PopupToolTip's loader must stay active while contentOpacity is still fading (DESIGN.md 2.5)")
for spec in ("elementMoveFast", "elementMoveExit"):
    check(spec in popup, f"PopupToolTip must name Appearance.animation.{spec} -- both directions (2.5)")

# -- Dialog: scrim, elevation 5, verylarge, decel in / accel out at ~half -----

check("colScrim" in dialog, "WindowDialog must dim what is behind it with colScrim (DESIGN.md 6.2)")
check("StyledRectangularShadow" in dialog, "WindowDialog sits at elevation 5 and needs its shadow (6.2)")
check(re.search(r"^\s*radius:\s*Appearance\.rounding\.verylarge\s*$", dialog, re.M),
      "WindowDialog's surface takes rounding.verylarge (DESIGN.md 9)")

handler = re.search(r"onShowChanged:\s*\{(.+?)^\s*\}", dialog, re.M | re.S)
check(handler, "WindowDialog must pick its spec in onShowChanged, not in a Behavior binding (2.9)")
if handler:
    body = handler.group(1)
    check("emphasizedDecel" in body and "emphasizedAccel" in body,
          "WindowDialog enters on emphasizedDecel and leaves on emphasizedAccel (DESIGN.md 9)")
    check(re.search(r"duration\s*=.*?/\s*2", body),
          "WindowDialog's exit runs at about half the enter's duration (DESIGN.md 2.5)")

# -- Family-wide: no radius-as-padding, no dividers, focus renders ------------

check(not (WIDGETS / "WindowDialogSeparator.qml").exists(),
      "WindowDialogSeparator is back -- 5.5 forbids divider lines")

for name in FAMILY:
    body = src(name)
    bad = re.findall(r"^\s*\w*[Pp]adding:\s*Appearance\.rounding\.\w+", body, re.M)
    check(not bad, f"{name} pads itself with a rounding token ({bad}) -- sharp mode zeroes it to 0")
    check(not re.search(r"implicitHeight:\s*1\b", body),
          f"{name} paints a hairline -- 5.5 separates with whitespace and layer cards")
    # Finding 1: a raw MouseArea that answers a click renders the focus film too.
    # (A RippleButton-rooted widget inherits it; check-button-states.py has those.
    # Scoped to the MouseArea's own block, so a DialogButton's onClicked further
    # down the file does not stand in for one.)
    for m in re.finditer(r"\bMouseArea\s*\{", body):
        depth, end = 0, m.end() - 1
        for j in range(end, len(body)):
            depth += (body[j] == "{") - (body[j] == "}")
            if depth == 0:
                end = j
                break
        if re.search(r"^\s*onClicked:", body[m.end():end], re.M):
            check("focused:" in body,
                  f"{name} answers a click through a MouseArea and renders no focus state "
                  "(DESIGN.md 3.1, brief finding 1)")

for msg in fails:
    print(f"FAIL {msg}")
print(f"{'FAILED' if fails else 'ok'}: dialog surfaces, {len(fails)} failure(s)")
sys.exit(1 if fails else 0)
