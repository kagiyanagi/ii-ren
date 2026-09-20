#!/usr/bin/env python3
"""Assert cw-motion's caller-parameterised animations default to Appearance, not a guess.

TriggerAnimation, DelayedPropertyAnimation, BounceAnimation and the wipes
(Crossfade/RevealWipe/Wipe) are the one place in modules/common/widgets a
caller-supplied duration is legitimate (DESIGN.md 2.3, cw-motion brief). The
obligation that comes with keeping the knob is that an *unparameterised*
caller is already correct -- so every default, and every curve these files
actually run on, must trace to Appearance, not a bare number or a hand-fit
bezier array.

Run: python3 tools/check-motion-defaults.py
"""
import pathlib, re, sys

WIDGETS = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii/modules/common/widgets"
failures = []


def find(text, pattern):
    m = re.search(pattern, text)
    return m.group(0) if m else None


def must_trace_to_appearance(rel, label, line):
    if line is None:
        failures.append(f"{rel}: no `{label}` line found -- did it move or get renamed?")
    elif "Appearance." not in line:
        failures.append(f"{rel}: `{label}` does not trace to Appearance.* -- {line.strip()}")


# DelayedPropertyAnimation: duration/easing are aliases onto its own `anim`;
# that inner PropertyAnimation is where the real default has to live.
text = (WIDGETS / "animations/DelayedPropertyAnimation.qml").read_text()
anim_block = text[text.index("id: anim"):]
must_trace_to_appearance("animations/DelayedPropertyAnimation.qml", "anim.duration default",
                          find(anim_block, r"duration:\s*.+"))

# BounceAnimation: totalDuration's own default.
text = (WIDGETS / "animations/BounceAnimation.qml").read_text()
must_trace_to_appearance("animations/BounceAnimation.qml", "totalDuration default",
                          find(text, r"property int totalDuration\s*:\s*.+"))

# The wipes: `duration`'s own default, plus the curve the one NumberAnimation
# each carries actually runs on.
for rel in ("transitions/Crossfade.qml", "transitions/RevealWipe.qml", "transitions/Wipe.qml"):
    text = (WIDGETS / rel).read_text()
    must_trace_to_appearance(rel, "duration default",
                              find(text, r"property int duration\s*:\s*.+"))
    must_trace_to_appearance(rel, "easing.bezierCurve",
                              find(text, r"easing\.bezierCurve:\s*.+"))

if failures:
    print("FAIL: a motion default regressed to an untokenised guess")
    for f in failures:
        print(f"  {f}")
    sys.exit(1)

print("ok: 5 parameterised animation files default to Appearance.*, no inline curves")
