#!/usr/bin/env python3
"""Assert a surface with nothing beneath it still has a background.

`Appearance.colors.colLayer1..4` and `colSurfaceContainer*` are not colours, they
are *overlays*: `solveOverlayColor(base, target, 1 - contentTransparency)` returns
the colour that, painted over `base` at alpha `1 - contentTransparency`, composites
to `target`. Inside a panel that is exact and invisible -- the layer below is
painted, so the result is the target to the last bit. On a surface that paints no
layer below it, the alpha is all that is left.

`backgroundTransparency` consults `transparency.enable`. `contentTransparency` did
not: it fell straight through to `autoContentTransparency`, which is 0.9. So with
the shipped config -- `enable: false`, `automatic: true`, i.e. transparency turned
*off* -- every content colour in the shell came back at alpha 0.1. Panels were
unaffected. Anything floating over a wallpaper was not: the region selector's
toolbar, the lock screen's three islands and the lock's PAM status bubble were all
painted at 10% over the wallpaper, which reads as nothing at all. Their
`RectangularShadow` is opaque and does not go through this, so what was left on
screen was a soft grey blob the exact shape of the card that should have been
there -- the shadow, with no card.

The gate is what this pins, in both directions:

- Both reals consult `enable`, and both fall back to 0. One without the other is
  the bug, and it is asymmetric enough to look deliberate.
- With transparency off the fills are opaque, so a base-less surface paints its
  container colour.
- Turning it off changes *only* those surfaces: the solved colour composited over
  its own base is the same pixel at the old alpha and at the new one, for every
  step of the layer chain. That is the licence for a one-line change to a token
  every widget in the shell reads, and it is palette-dependent, so it is computed
  rather than asserted from memory.

Ceiling: with transparency *enabled* those same base-less surfaces go back to
alpha `1 - 0.9`. Nested ones stay exact, because that is what the solve is for.
Fixing that means painting a base under the floating cards, not another token.

Run: python3 tools/check-content-transparency.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii"
appearance = (ROOT / "modules/common/Appearance.qml").read_text()
config = (ROOT / "modules/common/Config.qml").read_text()
toolbar = (ROOT / "modules/common/widgets/Toolbar.qml").read_text()
lock = (ROOT / "modules/ii/lock/LockSurface.qml").read_text()


def one(src: str, pattern: str, what: str) -> str:
    m = re.search(pattern, src)
    assert m, f"{what} no longer matches {pattern!r} -- this check is stale"
    return m.group(1).strip()


# --- the gate ----------------------------------------------------------------

GATE = r"Config\?\.options\.appearance\.transparency\.enable \? (.+) : 0$"

for name in ("backgroundTransparency", "contentTransparency"):
    binding = one(appearance, rf"property real {name}: (.+)", name)
    inner = re.fullmatch(GATE, binding)
    assert inner, (
        f"{name} does not consult transparency.enable. Every colour it feeds is a "
        "solveOverlayColor result whose alpha is 1 minus this number, so with the "
        "shipped automatic value the shell paints its content at alpha 0.1 while "
        "the user has transparency switched off. A panel hides that; a lock island "
        "or the region selector's toolbar has nothing under it and disappears, "
        "leaving only its shadow")
    assert "automatic" in inner.group(1), \
        f"{name} no longer honours transparency.automatic -- this check is stale"

# --- what the shipped config resolves to --------------------------------------

def default(option: str) -> str:
    block = one(config, r"(?s)property JsonObject transparency: JsonObject \{(.+?)\n\s*\}", "the transparency defaults")
    return one(block, rf"property (?:bool|real) {option}: (\S+)", f"the default {option}")


AUTO_CONTENT = float(one(appearance, r"property real autoContentTransparency: ([\d.]+)", "autoContentTransparency"))
assert default("enable") == "false", \
    "transparency now ships enabled -- the surfaces below are base-less either way, re-measure"
assert AUTO_CONTENT >= 0.5, \
    (f"autoContentTransparency is {AUTO_CONTENT}: the gate below is what keeps that off a "
     "surface with no layer under it, and this check exists because the number is high")

# --- the consequence, computed over the shipped palette -----------------------

m3 = {n: v for n, v in re.findall(r'property color (m3\w+): "(#[0-9a-fA-F]{6})"', appearance)}


def rgb(name: str) -> tuple[float, float, float]:
    h = m3[name]
    return tuple(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))


def solve(base: str, target: str, alpha: float) -> tuple[float, ...]:
    """ColorUtils.solveOverlayColor, clamp included."""
    b, t, inv = rgb(base), rgb(target), 1 - alpha
    return tuple(max(0.0, min(1.0, (t[i] - b[i] * inv) / alpha)) for i in range(3))


def over(overlay: tuple[float, ...], base: str, alpha: float) -> tuple[float, ...]:
    b = rgb(base)
    return tuple(overlay[i] * alpha + b[i] * (1 - alpha) for i in range(3))


# The chain as Appearance.qml declares it: each layer is solved against the one
# below, so a break anywhere in it is a break in every widget that nests.
CHAIN = [
    ("colLayer1", "m3background", "m3surfaceContainerLow"),
    ("colLayer2", "m3surfaceContainerLow", "m3surfaceContainer"),
    ("colLayer3", "m3surfaceContainer", "m3surfaceContainerHigh"),
    ("colLayer4", "m3surfaceContainerHigh", "m3surfaceContainerHighest"),
    ("colSurfaceContainerLow", "m3background", "m3surfaceContainerLow"),
    ("colSurfaceContainer", "m3surfaceContainerLow", "m3surfaceContainer"),
    ("colSurfaceContainerHigh", "m3surfaceContainer", "m3surfaceContainerHigh"),
    ("colSurfaceContainerHighest", "m3surfaceContainerHigh", "m3surfaceContainerHighest"),
]

OFF, WAS = 1.0, 1 - AUTO_CONTENT  # alpha with the gate, and without it

for token, base, target in CHAIN:
    assert re.search(rf"property color {token}: ColorUtils\.solveOverlayColor\(", appearance), \
        f"{token} is no longer a solved overlay -- this check is stale"

    # Nested: the same pixel before and after. This is the whole safety argument.
    for alpha in (WAS, OFF):
        err = max(abs(c - t) for c, t in zip(over(solve(base, target, alpha), base, alpha), rgb(target)))
        assert err * 255 < 0.5, (
            f"{token} composited over {base} at alpha {alpha:.2f} misses {target} by "
            f"{err * 255:.1f}/255 -- the solve clamped, so switching the gate is no longer "
            "a no-op for nested surfaces and this needs measuring rather than reasoning")

    # Base-less: what a floating card actually paints, with no layer under it.
    assert OFF == 1.0, f"{token} is not opaque with transparency off"

assert WAS < 0.2, \
    (f"the bug this guards paid out at alpha {WAS:.2f}, which is no longer small enough for the "
     "story above to be the story -- re-read it before trusting the gate")

# --- the surfaces that have nothing under them --------------------------------

# Toolbar is the widget in all three reports: the region selector's options bar and
# the lock screen's three islands are Toolbars, and it fills with a solved token.
assert re.search(r"color: Appearance\.colors\.colSurfaceContainer\b", toolbar), \
    ("Toolbar no longer fills with colSurfaceContainer -- if it moved to an opaque m3 token "
     "that is fine, but this check's second half is then pinning the wrong thing")
assert "enableShadow" in toolbar, \
    "Toolbar lost its shadow -- the symptom that reported this bug was the shadow left alone"
assert re.search(r"component LockIsland: Toolbar", lock), \
    "the lock islands are no longer Toolbars -- re-check what they fill with"
assert re.search(r"color: root\.statusFromPam \? Appearance\.colors\.colErrorContainer : Appearance\.colors\.colSurfaceContainer", lock), \
    "the lock status bubble's fill moved -- it floats over the wallpaper, so it needs an opaque one"

print("check-content-transparency: ok")
