#!/usr/bin/env python3
"""Assert the keystroke overlay actually shows the key that was just pressed.

One concern, two ways the surface lost it -- both invisible in a screenshot taken
at this machine's settings with a shortcut chip, which is exactly how they shipped.

**On screen.** The chip row is a horizontal ListView clamped to
`min(parent.width, contentWidth)`.
A ListView shows its *head*, and the newest chip is appended at the tail, so once
the row is wider than the screen the chip the overlay exists to show is the one the
edge cuts -- while four stale ones stay perfectly legible. Nothing about the code
looks wrong, and nothing on this machine shows it: the dev screen is 1920 wide at
the default five keys and scale 1.0, which fits. The settings page reaches it with
two sliders (twelve keys, scale 2.0), and merged typing gets there on a laptop.

So the fix is a pin -- `contentX: max(0, contentWidth - width)` -- and this file
evaluates the geometry across the whole reachable settings range rather than
trusting a screenshot taken at the one setting that never overflowed. The slider
bounds are lifted from the settings page, so widening a slider past what is checked
here fails rather than silently going unchecked.

**Opaque.** The window is `color: "transparent"` on the overlay layer, so a chip is
painted straight onto the recording with no shell layer beneath it. Every
`Appearance.colors.colSurfaceContainer*` is solved by `solveOverlayColor` and comes
back at alpha `1 - contentTransparency` -- 0.1 with the shipped config, because
`contentTransparency` falls through to `autoContentTransparency` without consulting
`transparency.enable`. Typed-text chips were drawn at 10%. Shortcut chips are
`m3primaryContainer`, which is opaque, so every screenshot of a shortcut looked
perfect. The fills are asserted against their definitions in Appearance.qml.

Run: python3 tools/check-keypress-display.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii"
qml = (ROOT / "modules/ii/keypressDisplay/KeypressDisplay.qml").read_text()
services = (ROOT / "modules/settings/ServicesConfig.qml").read_text()
appearance = (ROOT / "modules/common/Appearance.qml").read_text()
keypress_service = (ROOT / "services/KeypressService.qml").read_text()


def one(src: str, pattern: str, what: str) -> str:
    m = re.search(pattern, src)
    assert m, f"{what} no longer matches {pattern!r} -- this check is stale"
    return m.group(1).strip()


# --- structural: what the pin rests on ---------------------------------------

assert re.search(r"contentX: Math\.max\(0, contentWidth - width\)", qml), \
    "the chip row no longer pins its view to the tail -- the newest key is what the screen edge cuts"
assert re.search(r"interactive: false", qml), \
    "the chip row became interactive -- a flick writes contentX and kills the pin for good"
assert "Behavior on contentX" in qml, \
    "the pin has no Behavior -- every new chip teleports the whole row sideways"
assert "positionViewAt" not in qml, \
    "positionViewAt* writes contentX imperatively, which breaks the binding permanently"

# --- the numbers, lifted rather than transcribed -----------------------------

WIDTH_EXPR = one(qml, r"\n                width: (Math\.min\(.+)", "the chip row's width")
CONTENT_X_EXPR = one(qml, r"\n                contentX: (Math\.max\(.+)", "the chip row's scroll pin")
HUGE = int(one(appearance, r"property int huge: (\d+)", "Appearance.font.pixelSize.huge"))
MARGIN_H = int(one(qml, r"left: root\.keypressConfig\?\.marginH \?\? (\d+)", "the horizontal margin"))
SPACING = int(one(qml, r"spacing: (\d+)", "the chip row's spacing"))
PAD_RATIO = float(one(qml, r"horizontalPadding: chip\.fontSize \* ([\d.]+)", "the chip's padding"))
# A typed word stops merging at this many characters, so it is the widest chip
# the service can produce without the user holding a key down on one label.
MERGE_CAP = int(one(keypress_service, r"last\.label\.length < (\d+)", "the merge cap"))


def slider(option: str) -> tuple[float, float]:
    block = one(services, rf"(keypress\.{option}\n(?:.*\n){{0,4}}?\s*to: [\d.]+)", f"the {option} slider")
    return (float(one(block, r"from: ([\d.]+)", option)), float(one(block, r"to: ([\d.]+)", option)))


# --- opaque: nothing the chip paints may be a layer-composited colour ---------

assert 'color: "transparent"' in qml, \
    "the overlay window is no longer transparent -- the fill rule below may not apply any more"

fills = []
for role, expr in re.findall(r"(color|border\.color): (.+)", qml):
    for token in re.findall(r"Appearance\.(?:colors|m3colors)\.(\w+)", expr):
        # colPrimaryContainer is m3primaryContainer is a hex literal, so follow the
        # chain rather than stopping at the first name.
        name, seen = token, []
        for _ in range(5):
            definition = re.search(rf"property color {name}: (.+)", appearance)
            assert definition, f"Appearance.qml no longer defines {name} -- this check is stale"
            body = definition.group(1)
            assert "solveOverlayColor" not in body, (
                f"the chip's {role} resolves to {name}, which solveOverlayColor returns at alpha "
                "1 - contentTransparency (0.1 shipped). There is no layer under this window "
                "to composite it over, so it is painted onto the recording at that alpha. "
                "Use the opaque m3colors token, as the background widgets do over a wallpaper")
            seen.append(name)
            hop = re.fullmatch(r"(?:Appearance\.)?(?:colors|m3colors)\.(\w+)", body.strip().rstrip(";"))
            if not hop:
                break
            name = hop.group(1)
        fills.append(" -> ".join(seen))

MAX_KEYS = slider("maxKeys")
SCALE = slider("scale")
assert MAX_KEYS[1] <= 20, \
    (f"the maxKeys slider now reaches {MAX_KEYS[1]:.0f}: past ~20 repeats DESIGN.md 8 stops "
     "calling a per-delegate cached shadow cheap, and the delegate has one")

# DemiBold sans advances about 0.55em per character averaged over mixed case. The
# check is about the pin, not about font metrics, so this only has to be close
# enough to build rows that overflow -- and it is a floor, so real text is wider.
ADVANCE = 0.55


def js(text: str) -> str:
    """The two expressions, in the subset of JS they are written in."""
    return text.replace("Math.min(", "min(").replace("Math.max(", "max(").replace("parent.width", "parentWidth")


def row(keys: int, scale: float, chars: int, screen: int) -> tuple[float, float, float]:
    """(view width, contentX, right edge of the newest chip in content coords)."""
    font = HUGE * scale
    chip = round(chars * font * ADVANCE + font * PAD_RATIO * 2)
    env = {"min": min, "max": max,
           "parentWidth": screen - MARGIN_H * 2,
           "contentWidth": keys * chip + (keys - 1) * SPACING}
    width = eval(js(WIDTH_EXPR), {}, env)
    return width, eval(js(CONTENT_X_EXPR), {}, {**env, "width": width}), env["contentWidth"]


bad_without_pin = 0
checked = 0
for screen in (1366, 1920, 2560, 3840):
    for keys in range(int(MAX_KEYS[0]), int(MAX_KEYS[1]) + 1):
        for scale in (SCALE[0], 1.0, 1.5, SCALE[1]):
            for chars in (1, 6, 12, MERGE_CAP):
                width, content_x, newest_right = row(keys, scale, chars, screen)
                checked += 1

                # The newest chip ends at contentWidth; in view coordinates that
                # is contentWidth - contentX, and it has to be on screen.
                assert newest_right - content_x <= width + 0.5, (
                    f"{keys} keys of {chars} chars at scale {scale} on {screen}px: the newest chip "
                    f"ends {newest_right - content_x - width:.0f}px past the right edge of the row")
                assert content_x >= 0, f"contentX {content_x} scrolls before the first chip"
                # And the row never scrolls when it already fits.
                if newest_right <= width:
                    assert content_x == 0, f"a row that fits is scrolled to {content_x}"

                if newest_right > width:
                    bad_without_pin += 1

assert bad_without_pin > 0, \
    "no combination overflows any more -- this check proves nothing; widen the range or delete it"

print("ok: opaque fills " + "; ".join(sorted(set(fills))))
print(f"ok: newest chip visible in {checked} combinations "
      f"(1366..3840px, {MAX_KEYS[0]:.0f}..{MAX_KEYS[1]:.0f} keys, scale {SCALE[0]}..{SCALE[1]}); "
      f"{bad_without_pin} of them cut it before the pin")
sys.exit(0)
