#!/usr/bin/env python3
"""The wallpaper wipe spends its duration on the wipe, not on a tail.

`background.transitionDuration` is a user-facing knob, so it has to buy visible
animation across its whole range. It did not: every transition base ran on
`emphasizedDecel`, which is **half done at 6% of the duration** and spends the
remaining 94% creeping the last sliver of the old wallpaper into the corners.
Doubling the duration doubled the part nobody can see, so the reported symptom
was both "still too fast" and "a lot more delay than before" -- one cause, two
complaints that sound contradictory.

That curve is right for an element arriving at a resting position on screen.
Neither end of this travel is on screen: the mask starts as a point and
finishes past the far corner. So the reveal is linear, and this asserts it stays
that way -- the failure is silent, because the animation still *runs* for the
full duration either way and a still frame of a wipe proves nothing.

    python3 tools/check-wallpaper-transition.py
"""

import re
from pathlib import Path

SHELL = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
TRANSITIONS = SHELL / "modules/common/widgets/transitions"

# Bases that drive a reveal. The named styles in the settings combo are thin
# wrappers over these: Radial/Diamond/Outer/Slash -> RevealWipe, Wave -> Wipe.
BASES = ["RevealWipe.qml", "Wipe.qml", "Crossfade.qml"]
WRAPPERS = {"Radial.qml": "RevealWipe", "Diamond.qml": "RevealWipe", "Outer.qml": "RevealWipe",
            "Slash.qml": "RevealWipe", "Wave.qml": "Wipe"}


def cubic(p, t):
    """One cubic bezier segment, P0..P3 as (x, y) pairs."""
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = p
    m = 1 - t
    return (m**3 * x0 + 3 * m * m * t * x1 + 3 * m * t * t * x2 + t**3 * x3,
            m**3 * y0 + 3 * m * m * t * y1 + 3 * m * t * t * y2 + t**3 * y3)


def profile(points):
    """(fraction of duration) at which the travel is 50%, 90%, 99% done."""
    samples = [cubic(points, i / 4000) for i in range(4001)]
    out = []
    for target in (0.5, 0.9, 0.99):
        out.append(next((x for x, y in samples if y >= target), 1.0))
    return out


LINEAR = [(0, 0), (1 / 3, 1 / 3), (2 / 3, 2 / 3), (1, 1)]
# Appearance.animationCurves.emphasizedDecel, as it was declared here.
EMPHASIZED_DECEL = [(0, 0), (0.05, 0.7), (0.1, 1.0), (1, 1)]

# 1. What the knob has to buy. A reveal is "even" when half of it has not
#    already happened in the first third of the duration, and when the last
#    percent does not own a quarter of it.
def assert_even(name, points):
    half, ninety, ninetynine = profile(points)
    assert half >= 0.35, f"{name}: half the reveal is over by {half:.0%} of the duration"
    assert ninety >= 0.7, f"{name}: 90% of the reveal is over by {ninety:.0%} of the duration"
    assert ninetynine >= 0.9, f"{name}: the last 1% owns {1 - ninetynine:.0%} of the duration"


assert_even("linear", LINEAR)

# 2. The curve this replaced fails all three, which is why the guard exists.
half, ninety, ninetynine = profile(EMPHASIZED_DECEL)
assert half <= 0.1, "emphasizedDecel no longer front-loads; re-derive this check"
assert ninety <= 0.4, "emphasizedDecel no longer front-loads; re-derive this check"
failed = False
try:
    assert_even("emphasizedDecel", EMPHASIZED_DECEL)
except AssertionError:
    failed = True
assert failed, "the evenness test does not catch the curve it was written for"

# 3. No reveal may go back to a bezier. Any bezier this repo declares that is
#    spatial or effects is shaped for an element arriving somewhere; none of
#    them are even enough, so the source has to say Linear.
for name in BASES:
    src = (TRANSITIONS / name).read_text()
    body = re.sub(r"//[^\n]*", "", src)
    anim = re.search(r"NumberAnimation\s*\{(.+?)\n    \}", body, re.S)
    assert anim, f"{name}: no reveal animation found"
    block = anim.group(1)
    assert "Easing.Linear" in block, f"{name}: the reveal is not linear any more"
    assert "bezierCurve" not in block, f"{name}: a bezier came back to the reveal"
    # The duration stays a property the caller binds, never a number here.
    assert re.search(r"duration:\s*effect\.duration", block), f"{name}: duration stopped being the caller's"

# 4. Every style the settings combo offers still lands on one of those bases.
COMBO = ["radial", "crossfade", "wipe", "diamond", "slash", "outer", "wave"]
settings = (SHELL / "modules/settings/BackgroundConfig.qml").read_text()
for style in COMBO:
    assert f'value: "{style}"' in settings, f"{style} left the settings combo"
    qml = TRANSITIONS / (style.capitalize() + ".qml")
    assert qml.exists(), f"{style} has no transition file"
    if qml.name in WRAPPERS:
        assert WRAPPERS[qml.name] in qml.read_text(), f"{qml.name} no longer wraps {WRAPPERS[qml.name]}"

# 5. The knob reaches the animation, and radial keeps its 10%: its circle
#    crosses the diagonal while the others cross an edge.
ti = (SHELL / "modules/common/widgets/TransitionImage.qml").read_text()
assert "Config.options.background.transitionDuration" in ti, "the duration knob is disconnected"
assert re.search(r'transitionType === "radial" \? 1\.1 : 1', ti), "radial lost its 10%"
assert re.search(r"item\.duration = Qt\.binding", ti), "the effect stopped following the knob"

cfg = (SHELL / "modules/common/Config.qml").read_text()
default = re.search(r"property int transitionDuration:\s*(\d+)", cfg)
assert default, "background.transitionDuration is gone"
assert 200 <= int(default.group(1)) <= 6000, "the default sits outside the spin box's range"

print("ok: the wallpaper wipe travels at one speed, so the duration knob buys "
      f"animation rather than tail (default {default.group(1)}ms)")
