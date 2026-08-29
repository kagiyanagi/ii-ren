#!/usr/bin/env python3
"""Assert the Hyprland spring curves still match Android 16's motion tokens.

dampening is a damping *coefficient*, but AOSP publishes a damping *ratio*, so the
numbers in general.lua are derived: c = 2 * zeta * sqrt(stiffness * mass). A typo there
silently changes the feel instead of erroring, hence this check.

Source of truth: androidx.compose.material3.tokens.ExpressiveMotionTokens (AOSP).
Run: python3 tools/check-m3-springs.py
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
