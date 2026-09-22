#!/usr/bin/env python3
"""The on-screen keyboard opens, closes visibly, and can reach its own layouts.

Three of the four things here have no symptom a screenshot can show.

* The **exit**. `Loader.active` must not read `GlobalStates.oskOpen`, not even as one
  half of an `||`. The binding and the `Connections` that starts the exit hang off the
  same change signal in an undefined order, and when the binding wins the component is
  destroyed before the handler runs. Measured that way round: the close handler never
  executed once, and the layer unmapped 45ms after the request instead of playing the
  130ms exit. With the latch owned solely by the component it holds ~180ms.
* The **rise is an anchor margin, never a transform.** The window masks the card, and
  `mask: Region` computes its input region from the item's rect *with transforms
  applied* and refreshes it only on a geometry change -- a card resting at a scale is
  painted full size while every click goes to the window behind it.
* The **layout knob was dead.** `Config.options.osk.layout` shipped as `"qwerty_full"`,
  which is not a key in `layouts.js`, so it fell back for everyone and the other two
  layouts were unreachable: there is no settings page for the OSK, and the only way in
  was to guess the exact display name. The cycler must also survive that config, which
  is why it cycles from the *resolved* name.
* The **key grid is data-driven.** Every shape in `layouts.js` gets its width from a
  multiplier table that does not list `space`, `expand` or `empty`; the old expression
  `baseWidth * widthMultiplier[shape] || baseWidth` only worked because NaN is falsy,
  and a shape whose multiplier is legitimately 0 would have silently become 48.

Run: python3 tools/check-osk.py
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OSK = ROOT / "dots/.config/quickshell/ii/modules/ii/onScreenKeyboard"
CONFIG_QML = ROOT / "dots/.config/quickshell/ii/modules/common/Config.qml"
SHIPPED_JSON = ROOT / "dots/.config/illogical-impulse/config.json"

kbd = (OSK / "OnScreenKeyboard.qml").read_text()
content = (OSK / "OskContent.qml").read_text()
key = (OSK / "OskKey.qml").read_text()
layouts_js = (OSK / "layouts.js").read_text()


# ── the layout data, parsed out of the JS object literal ─────────────────────

FIELD = re.compile(r'''(\w+):\s*(?:"((?:[^"\\]|\\.)*)"|'([^']*)'|([\w.]+))''')


def entry(src):
    """One `{a: "b", c: 3}` literal as a flat {name: string} dict."""
    return {m.group(1): next((g for g in m.groups()[1:] if g is not None), "")
            for m in FIELD.finditer(src)}


def parse_layouts():
    """`byName` from layouts.js as {display name: {short, rows: [[key, ...], ...]}}.

    The file is a JS module, not JSON -- unquoted keys and single-quoted values --
    so it is read with regexes. Everything downstream needs is names and shapes.
    """
    src = re.sub(r"//[^\n]*", "", layouts_js)
    out = {}
    for m in re.finditer(r'\n    "([^"]+)": \{(.*?)\n    \}', src, re.S):
        name, body = m.group(1), m.group(2)
        short = re.search(r'name_short:\s*"([^"]*)"', body)
        rows = [[entry(k) for k in re.findall(r"\{([^{}]*)\}", rowsrc)]
                for rowsrc in re.findall(r"\n            \[(.*?)\n            \]", body, re.S)]
        out[name] = {"short": short.group(1) if short else None, "rows": rows}
    return out


LAYOUTS = parse_layouts()
assert len(LAYOUTS) >= 3, f"layouts.js should hold at least 3 layouts, found {list(LAYOUTS)}"
for name, l in LAYOUTS.items():
    assert l["short"], f"{name} has no name_short -- the rail button renders it"
    assert len(l["short"]) <= 3, f"{name}'s name_short {l['short']!r} will not fit a 40dp button"


# ── 1. the config default has to name a layout that exists ───────────────────

default_qml = re.search(r'property string layout:\s*"([^"]*)"', CONFIG_QML.read_text())
assert default_qml, "Config.qml no longer declares osk.layout"
assert default_qml.group(1) in LAYOUTS, (
    f"Config.qml defaults osk.layout to {default_qml.group(1)!r}, which is not a key in "
    f"layouts.js ({sorted(LAYOUTS)}). It shipped as 'qwerty_full' and fell back for "
    f"everyone -- there is no settings page for the OSK, so nothing else reaches the knob."
)
shipped = json.loads(SHIPPED_JSON.read_text())["osk"]["layout"]
assert shipped in LAYOUTS, (
    f"the shipped config.json names layout {shipped!r}, absent from layouts.js"
)

js_default = re.search(r'const defaultLayout = "([^"]*)"', layouts_js).group(1)
assert js_default in LAYOUTS, f"layouts.js defaultLayout {js_default!r} is not one of its own layouts"


# ── 2. cycleLayout, evaluated ────────────────────────────────────────────────

def resolve(cfg_name):
    """OskContent.activeLayoutName."""
    return cfg_name if cfg_name in LAYOUTS else js_default


def cycle(cfg_name):
    """OskContent.cycleLayout(), from the *resolved* name."""
    names = list(LAYOUTS)
    return names[(names.index(resolve(cfg_name)) + 1) % len(names)]


names = list(LAYOUTS)
seen, cur = [], names[0]
for _ in range(len(names)):
    cur = cycle(cur)
    seen.append(cur)
assert sorted(seen) == sorted(names), f"cycling does not reach every layout: {seen}"
assert seen[-1] == names[0], f"cycling {len(names)} times should return to {names[0]}, got {seen[-1]}"

# The shipped-but-invalid name is the case the config was actually in.
assert cycle("qwerty_full") == names[1], (
    "cycling from a config name that matches no layout must land on the layout after the "
    f"resolved one, not nowhere -- got {cycle('qwerty_full')!r}"
)
assert "indexOf(root.activeLayoutName)" in content, (
    "cycleLayout must index the *resolved* name; indexing Config.options.osk.layout "
    "returns -1 for the shipped default and the first press then goes to the wrong layout"
)


# ── 3. the exit: the latch may not read the open flag ────────────────────────

active = re.search(r"\n\s*active:\s*(.+)", kbd)
assert active, "the OSK Loader no longer declares `active`"
assert "GlobalStates.oskOpen" not in active.group(1), (
    f"Loader.active is `{active.group(1).strip()}` -- it must not read oskOpen. The "
    "binding and the Connections that starts the exit fire on the same change signal in "
    "an undefined order; when the binding wins, the surface is destroyed before the exit "
    "can start and the keyboard vanishes on the frame the flag clears."
)
latch = active.group(1).strip()
assert re.fullmatch(r"root\.\w+", latch), f"Loader.active should be one latched property, got {latch!r}"
latch_prop = latch.split(".")[1]

clears = re.findall(rf"root\.{latch_prop}\s*=\s*false", kbd)
assert len(clears) == 1, f"{latch_prop} must be cleared in exactly one place, found {len(clears)}"
assert re.search(
    rf"onOpenedProgressChanged:.*?openedProgress === 0[^\n]*\n[^\n]*root\.{latch_prop} = false",
    kbd, re.S,
), f"{latch_prop} must only be cleared once the exit has actually landed at 0"
assert "!GlobalStates.oskOpen" in kbd, (
    "clearing the latch has to check the surface is still meant to be closing, or a "
    "re-open that arrives on the last frame of the exit tears the surface down again"
)

# Both directions, and the right spec for each (DESIGN.md 2.5).
assert "Appearance.animation.elementMoveEnter" in kbd, "no enter spec"
assert "Appearance.animation.elementMoveExit" in kbd, "no exit spec"
assert re.search(r"if \(GlobalStates\.oskOpen\) \{\s*\n\s*oskRoot\.openSpec = Appearance\.animation\.elementMoveEnter",
                 kbd), "the open branch must select the enter spec"
assert re.search(r"\} else \{\s*\n\s*oskRoot\.openSpec = Appearance\.animation\.elementMoveExit",
                 kbd), "the close branch must select the exit spec"
assert "onVisibleChanged" in kbd, (
    "without a kickoff on visible, the rise is assigned during construction and most of "
    "it plays before the first frame reaches the screen"
)


# ── 4. the rise is an anchor margin, and the mask has no transform ───────────

masked = re.search(r"mask:\s*Region\s*\{[^}]*item:\s*(\w+)", kbd)
assert masked and masked.group(1) == "oskBackground", "the window should mask the card"
# The card's own properties only: its nested children may transform freely, since
# `Region` takes the masked item's rect and nothing below it. Comments are stripped
# first -- the comment explaining this trap names every word the check looks for.
card_block = re.search(r"id: oskBackground(.*?)\n            \}", kbd, re.S).group(1)
card = "\n".join(re.sub(r"//.*", "", ln) for ln in card_block.splitlines()
                 if re.match(r"\s{16}\w", ln))
for banned in ("scale:", "transform:", "transformOrigin:", "rotation:"):
    assert banned not in card, (
        f"oskBackground sets {banned} and is the masked item -- `mask: Region` bakes the "
        "transform into the input region and refreshes it only on a geometry change, so "
        "the card paints at full size and every click goes to the window behind it"
    )
assert "anchors.bottomMargin: Appearance.sizes.elevationMargin - height * (1 - oskRoot.openedProgress)" in kbd, (
    "the rise must travel on the bottom anchor margin (geometry, which re-bakes the mask), "
    "out of the screen edge the panel is anchored to (DESIGN.md 2.6)"
)


# ── 5. key geometry: every shape in the data resolves to a real size ─────────

def table(name):
    body = re.search(rf"property var {name}: \(\{{(.*?)\}}\)", key, re.S).group(1)
    return {k: float(v) for k, v in re.findall(r'"(\w+)":\s*([\d.]+)', body)}


W, H = table("widthMultiplier"), table("heightMultiplier")
base = float(re.search(r"property real baseWidth: ([\d.]+)", key).group(1))
baseh = float(re.search(r"property real baseHeight: ([\d.]+)", key).group(1))
assert base % 4 == 0 and baseh % 4 == 0, f"the key unit {base}x{baseh} is off the 4dp grid"
assert base >= 48, f"a key is {base}px; AOSP's minimum touch target is 48dp (DESIGN.md 3.4)"

assert len(re.findall(r"Multiplier\[shape\] \?\? 1", key)) == 2, (
    "both multiplier lookups must fall back with `?? 1`. `baseWidth * widthMultiplier[shape] "
    "|| baseWidth` only worked because `48 * undefined` is NaN and NaN is falsy -- a shape "
    "whose multiplier is legitimately 0 would silently become a full-width key."
)
assert key.count("Math.round(") == 2, (
    "both implicit sizes must be rounded; a RowLayout hands a fractional width straight "
    "to the glyph rasteriser"
)

shapes = {k.get("shape") for l in LAYOUTS.values() for r in l["rows"] for k in r}
shapes.discard(None)
for s in sorted(shapes):
    w = round(base * W.get(s, 1))
    h = round(baseh * H.get(s, 1))
    assert h >= 32, f"shape {s!r} is {h}px tall; 32px is the pointer-target floor (DESIGN.md 3.4)"
    assert w >= 32, f"shape {s!r} is {w}px wide"

# The widest row plus the rail and the padding has to fit a small laptop panel.
RAIL, PAD, GAP = 40, 12, 4
for name, l in LAYOUTS.items():
    assert l["rows"], f"{name} parsed to no rows"
    widest = max(sum(round(base * W.get(k.get("shape"), 1)) for k in r) + GAP * (len(r) - 1)
                 for r in l["rows"])
    total = widest + RAIL + GAP * 3 + PAD * 2
    assert total <= 1280, f"{name} needs {total}px of width; it must fit a 1280px panel"


# ── 6. a word label steps down, or it elides on a key wide enough for it ─────

assert "keyText.text.length > 1" in key, (
    'a multi-character label must drop to pixelSize.small. At `large`, "Menu" elided to '
    '"Me..." on a 48px key, and no other check in the repo looks at rendered text width.'
)
assert re.search(r"font\.pixelSize:.*isBackspace \|\| isEnter", key, re.S), (
    "the icon labels must be picked before the word rule, or backspace/enter (whose text "
    "is a Material Symbol name) get the small size and render as tiny glyphs"
)

print(f"ok  osk: {len(LAYOUTS)} layouts reachable ({', '.join(l['short'] for l in LAYOUTS.values())}), "
      f"exit latched off `{latch_prop}`, rise on the bottom anchor margin, "
      f"{base:.0f}px keys")
