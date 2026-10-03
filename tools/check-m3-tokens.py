#!/usr/bin/env python3
"""Assert the M3 tokens copied out of AOSP still match what AOSP says.

dampening is a damping *coefficient*, but AOSP publishes a damping *ratio*, so the
numbers in general.lua are derived: c = 2 * zeta * sqrt(stiffness * mass). A typo there
silently changes the feel instead of erroring, hence this check.

It also holds Appearance's bezier curves and durations to the values M3 publishes,
and the state layer opacities to StateTokens, for the same reason: a wrong digit
animates fine and just feels off.

Source of truth: androidx.compose.material3.tokens.ExpressiveMotionTokens (AOSP),
and m3.material.io (mirror it with tools/m3-docs.py; distilled in .github/M3.md).
Run: python3 tools/check-m3-tokens.py
"""
import math, pathlib, re, sys

# curve name -> (md.sys.motion.spring.*.stiffness, dampingRatio)
TOKENS = {
    "m3FastSpatial": (800, 0.6),
    "m3DefaultSpatial": (380, 0.8),
    "m3SlowSpatial": (200, 0.8),
    "m3FastEffects": (3800, 1.0),
    "m3DefaultEffects": (1600, 1.0),
    "m3SlowEffects": (800, 1.0),
}
CURVE = re.compile(
    r'hl\.curve\("(\w+)",\s*{\s*type\s*=\s*"spring",\s*mass\s*=\s*([\d.]+),'
    r'\s*stiffness\s*=\s*([\d.]+),\s*dampening\s*=\s*([\d.]+)\s*}'
)

src = (pathlib.Path(__file__).parent.parent / "dots/.config/hypr/hyprland/general.lua").read_text()
found = {m[1]: (float(m[2]), float(m[3]), float(m[4])) for m in CURVE.finditer(src)}

assert set(found) == set(TOKENS), f"curve set drifted: {sorted(found)} != {sorted(TOKENS)}"
for name, (mass, stiffness, dampening) in found.items():
    want_k, zeta = TOKENS[name]
    assert stiffness == want_k, f"{name}: stiffness {stiffness} != token {want_k}"
    want_c = 2 * zeta * math.sqrt(want_k * mass)
    assert abs(dampening - want_c) < 5e-4, f"{name}: dampening {dampening} != {want_c:.4f} (zeta {zeta})"
    # Hyprland rejects any of these below 0.5.
    assert min(mass, stiffness, dampening) >= 0.5, f"{name}: Hyprland requires mass/stiffness/dampening >= 0.5"
print(f"ok: {len(found)} springs match Android 16 motion tokens")

# State layer opacities: androidx.compose.material3.tokens.StateTokens.
# mix(base, on, p) keeps p of the base colour, so an 8% layer is p = 0.92.
STATE = {"Hover": 0.08, "Active": 0.10}  # Hover/Pressed StateLayerOpacity
# The same table again, this time as StateLayer.qml's switch. Appearance bakes the
# film into a colour; StateLayer paints it as a film, and both must agree.
STATE_LAYER = {"Hover": 0.08, "Focus": 0.1, "Press": 0.1, "Drag": 0.16}
LAYER = re.compile(
    r"colLayer(\d)(Hover|Active):.*?ColorUtils\.mix\(colLayer\d(?:Base)?, colOnLayer\d, ([\d.]+)\)"
)

qml = (pathlib.Path(__file__).parent.parent
       / "dots/.config/quickshell/ii/modules/common/Appearance.qml").read_text()
layers = LAYER.findall(qml)
assert len(layers) == 10, f"expected 5 layers x 2 states, found {len(layers)}"
for num, state, kept in layers:
    want = 1 - STATE[state]
    assert abs(float(kept) - want) < 1e-9, \
        f"colLayer{num}{state}: keeps {kept} of the base, token wants {want:.2f}"
print(f"ok: {len(layers)} state layers match StateTokens")

sl = (pathlib.Path(__file__).parent.parent
      / "dots/.config/quickshell/ii/modules/common/widgets/StateLayer.qml").read_text()
cases = dict(re.findall(r"case StateLayer\.State\.(\w+):\s*return ([\d.]+);", sl))
assert set(cases) == set(STATE_LAYER), f"StateLayer states drifted: {sorted(cases)}"
for state, opacity in cases.items():
    assert abs(float(opacity) - STATE_LAYER[state]) < 1e-9, \
        f"StateLayer {state}: {opacity} != token {STATE_LAYER[state]}"
print(f"ok: {len(cases)} StateLayer opacities match StateTokens")

# Appearance's bezier curves against M3's published values: the easing tokens
# (md.sys.motion.easing.*) and the spring->curve conversions on m3.material.io ->
# Motion -> Specs. Qt's BezierSpline lists control points then the end point, so
# M3's (x1, y1, x2, y2) is [x1, y1, x2, y2, 1, 1] here. Fast and slow effects are
# left out on purpose: M3 gives them their own curves (0.31, 0.94, 0.34, 1 @150ms;
# 0.34, 0.88, 0.34, 1 @300ms), Appearance reuses default effects at 130/280, and
# that is an open decision (M3.md 1.2), not a typo to assert away.
CURVES = {
    "expressiveFastSpatial": [0.42, 1.67, 0.21, 0.90],
    "expressiveDefaultSpatial": [0.38, 1.21, 0.22, 1.00],
    "expressiveSlowSpatial": [0.39, 1.29, 0.35, 0.98],
    "expressiveEffects": [0.34, 0.80, 0.34, 1.00],
    "emphasizedDecel": [0.05, 0.7, 0.1, 1],
    "emphasizedAccel": [0.3, 0, 0.8, 0.15],
    "standard": [0.2, 0, 0, 1],
    "standardDecel": [0, 0, 0, 1],
    "standardAccel": [0.3, 0, 1, 1],
}
# md.sys.motion.easing.emphasized on Android, a two-segment path.
EMPHASIZED = [0.05, 0, 0.133333, 0.06, 0.166666, 0.4, 0.208333, 0.82, 0.25, 1, 1, 1]
DURATIONS = {"expressiveFastSpatialDuration": 350, "expressiveDefaultSpatialDuration": 500,
             "expressiveSlowSpatialDuration": 650, "expressiveEffectsDuration": 200}


def qml_list(name):
    m = re.search(rf"property list<real> {name}: \[([^\]]*)\]", qml)
    assert m, f"Appearance.animationCurves.{name} is gone"
    return [eval(x, {"__builtins__": {}}) for x in m.group(1).split(",")]  # digits and / only


for name, points in CURVES.items():
    got = qml_list(name)
    assert all(abs(a - b) < 1e-6 for a, b in zip(got, points + [1, 1])) and len(got) == 6, \
        f"{name}: {got} != M3 {points}"
got = qml_list("emphasized")
assert len(got) == 12 and all(abs(a - b) < 1e-5 for a, b in zip(got, EMPHASIZED)), f"emphasized: {got}"
for name, ms in DURATIONS.items():
    m = re.search(rf"property real {name}: (\d+)", qml)
    assert m and int(m.group(1)) == ms, f"{name} != M3's {ms}ms"
print(f"ok: {len(CURVES) + 1} curves and {len(DURATIONS)} durations match M3")
