#!/usr/bin/env python3
"""Assert DESIGN.md 8's effect budget where a script can see it.

Two things, both invisible to check-design.py because both are about *where* a
line sits rather than what it says:

1. No expensive effect inside a repeated delegate (DESIGN.md 8, anti-pattern
   10.11). A `layer.enabled`, an `OpacityMask` or a blur costs one framebuffer
   *per row*, so a list that looks fine at three items melts at thirty. The fix
   is always the same: cache it at the container, or drop it. The shell already
   had a dozen of these when the rule was first checked, so this is a
   shrink-only gate -- KNOWN is the list as it stood, and it may only get
   shorter. A new one fails the build.

2. `StyledDropShadow.samples` does not follow `radius`. Qt recompiles the blur
   shader every time `samples` changes and says so in its own docs; the widget
   used to derive it as `radius * 2 + 1`, and DockAppButton animates `radius` on
   hover, so a hover recompiled the shader every frame. Measured on Iris Xe at
   1 and 8 shadows, 26-69% more frames once the two were decoupled. Nothing
   about the expression looks wrong, which is exactly why it needs a test.

Run: python3 tools/check-effect-budget.py
"""
import pathlib
import re

SHELL = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii"

# Expensive per DESIGN.md 8. RectangularShadow is deliberately absent: it is
# analytic and cached, and 8 lists it as cheap.
EFFECT = re.compile(
    r"\b(layer\.enabled\s*:\s*(?!false\b)"
    r"|MultiEffect\s*\{|OpacityMask\s*\{|ShaderEffect\s*\{"
    r"|StyledBlurEffect\s*\{|StyledDropShadow\s*\{"
    r"|DropShadow\s*\{|GaussianBlur\s*\{|FastBlur\s*\{|RecursiveBlur\s*\{"
    r"|ColorOverlay\s*\{|Glow\s*\{)")

# A Repeater has no children but its delegate, so its whole body is delegate
# scope. A view's body is not: `layer.enabled` on a ListView is the recommended
# fix, not the violation, so only its `delegate:` counts.
REPEATER = re.compile(r"\bRepeater\s*\{")
DELEGATE = re.compile(r"\bdelegate\s*:\s*\w*\s*\{")

# Effects nested in a delegate as of the cw-effects audit. Shrink only.
KNOWN = {
    ("modules/common/widgets/Carousel.qml", "OpacityMask"),
    ("modules/common/widgets/Carousel.qml", "layer.enabled"),
    ("modules/ii/background/widgets/DateWidget/CalendarAgendaWidget.qml", "DropShadow"),
    ("modules/ii/background/widgets/bluetooth/BluetoothFillCardsWidget.qml", "OpacityMask"),
    ("modules/ii/background/widgets/bluetooth/BluetoothFillCardsWidget.qml", "StyledDropShadow"),
    ("modules/ii/background/widgets/bluetooth/BluetoothFillCardsWidget.qml", "layer.enabled"),
    ("modules/ii/background/widgets/bluetooth/DevicesBatteryList1x1Widget.qml", "OpacityMask"),
    ("modules/ii/background/widgets/bluetooth/DevicesBatteryList1x1Widget.qml", "layer.enabled"),
    ("modules/ii/background/widgets/bluetooth/DevicesBatteryListWidget.qml", "OpacityMask"),
    ("modules/ii/background/widgets/bluetooth/DevicesBatteryListWidget.qml", "layer.enabled"),
    ("modules/ii/background/widgets/utility/ResourceFillCardsWidget.qml", "OpacityMask"),
    ("modules/ii/background/widgets/utility/ResourceFillCardsWidget.qml", "layer.enabled"),
    # Workspaces' monochrome icons: this IS this gate's own prescribed fix,
    # not a violation being silenced. It used to be a Desaturate *and* a
    # ColorOverlay on every app icon, and the option is on by default. Both
    # collapsed into one MultiEffect cached at the icon row -- "cache it at the
    # container", exactly as the assertion says -- so the cost went from two
    # framebuffers per icon to one per workspace. It still reads as nested
    # because that container sits inside the per-workspace Repeater, and it
    # cannot rise any further: one level up holds the number and the dot, which
    # must not be desaturated. Anything that lands here without that argument is
    # a real hit.
    ("modules/ii/bar/Workspaces.qml", "layer.enabled"),
    ("modules/ii/bar/Workspaces.qml", "MultiEffect"),
    ("modules/ii/desktopMenu/DesktopMenu.qml", "OpacityMask"),
    ("modules/ii/desktopMenu/DesktopMenu.qml", "layer.enabled"),
    ("modules/ii/dock/widgets/DockPreviewPopup.qml", "OpacityMask"),
    ("modules/ii/dock/widgets/DockPreviewPopup.qml", "layer.enabled"),
}


def uncommented(src: str) -> str:
    """Blank out comments, keeping offsets so line numbers stay true."""
    src = re.sub(r"//[^\n]*", lambda m: " " * len(m.group()), src)
    return re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group()), src, flags=re.S)


def block_end(src: str, start: int) -> int:
    """`start` indexes the opening brace; returns the index of its partner."""
    depth = 0
    for i in range(start, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    return len(src)


found = {}
for path in sorted(SHELL.rglob("*.qml")):
    if "user_widgets" in path.parts:
        continue  # installed extensions are not ours to gate
    src = uncommented(path.read_text())
    scopes = [(m.end() - 1, block_end(src, m.end() - 1))
              for pattern in (REPEATER, DELEGATE) for m in pattern.finditer(src)]
    for start, end in scopes:
        for hit in EFFECT.finditer(src, start, end):
            name = hit.group(1).split("{")[0].split(":")[0].strip()
            key = (str(path.relative_to(SHELL)), name)
            found.setdefault(key, src.count("\n", 0, hit.start()) + 1)

new = sorted(k for k in found if k not in KNOWN)
assert not new, "effect nested in a repeated delegate (DESIGN.md 8, 10.11):\n" + "\n".join(
    f"  {f}:{found[(f, n)]}  {n}  -- cache it at the container or drop it" for f, n in new)

drop = KNOWN - set(found)

shadow = (SHELL / "modules/common/widgets/StyledDropShadow.qml").read_text()
assert not re.search(r"^\s*samples:.*\bradius\b", shadow, re.M), \
    ("StyledDropShadow: `samples` must not be derived from `radius` -- a caller "
     "animating radius then recompiles the blur shader every frame")
assert re.search(r"^\s*samples:", shadow, re.M), \
    "StyledDropShadow: no `samples` at all -- Qt's default 9 under-samples the blur"

print(f"ok: no new effect in a repeated delegate ({len(KNOWN) - len(drop)} known, "
      f"{len(drop)} fixed), StyledDropShadow keeps samples off radius")
if drop:
    print("   fixed since the audit, drop from KNOWN: "
          + ", ".join(f"{f}:{n}" for f, n in sorted(drop)))
