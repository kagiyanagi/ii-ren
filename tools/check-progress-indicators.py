#!/usr/bin/env python3
"""Assert that the progress family's timings come from AOSP, not from callers.

`CircularProgress` and `ClippedFilledCircularProgress` used to export
`animationDuration` and `easingType` as properties. That is the shape
`.audit/common-widgets/brief.md` calls the worst of its three motion findings:
it does not merely violate "never invent a number", it hands every call site a
place to invent one, in a file `check-design.py` will never connect back to the
widget. So the knobs are gone, and this is what keeps them gone.

The rest is the contract those widgets are supposed to meet, none of which has a
line for `check-design.py` to flag:

  * A determinate indicator must not overshoot. AOSP animates progress with
    `ProgressIndicatorDefaults.ProgressAnimationSpec` -- a `DampingRatioNoBouncy`
    spring (`ProgressIndicator.kt`) -- because a bar that swings past the value
    and comes back is reporting a number that never happened. The geometry is
    spatial but the spec must be one that clips, and DESIGN.md 2.1 does not say
    so, because 2.1 is about media, not meaning.
  * `StyledIndeterminateProgressBar`'s sweep is a transcription. A transcription
    with a typo in it is indistinguishable from a hand fit, and every window has
    to close inside the cycle or a segment stalls at the edge.
  * `SineCookie` must not rebuild its 361-point path from a frame clock again.

  python3 tools/check-progress-indicators.py
"""
import pathlib, re, sys

QML = pathlib.Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
WIDGETS = QML / "modules/common/widgets"
fails = []


def check(cond, msg):
    if not cond:
        fails.append(msg)


def src(name):
    """The widget's code, minus its comments -- a checker a prose sentence can
    trip is a checker someone silences instead of reading. `(?<!:)` spares the
    `//` of a URL."""
    body = re.sub(r"/\*.*?\*/", "", (WIDGETS / f"{name}.qml").read_text(), flags=re.S)
    return re.sub(r"(?<!:)//.*", "", body)


# --- 1. The knobs stay dead, both as API and at every call site.
# TransitionImage's own animationDuration is cw-motion's, and legitimate: the
# brief makes the transition family the one place a caller picks a duration.
KNOB_OWNER = "TransitionImage.qml"
for knob in ("animationDuration", "easingType"):
    users = sorted(
        p.relative_to(QML).as_posix()
        for p in QML.rglob("*.qml")
        if re.search(rf"\b{knob}\b", p.read_text(errors="replace")) and p.name != KNOB_OWNER
    )
    check(not users, f"`{knob}` is back, in: {', '.join(users)} -- "
                     f"a progress widget's timing comes from Appearance, not its caller")

# --- 2. Determinate progress animates its value without overshooting.
NO_OVERSHOOT = ("elementMoveFast", "elementMoveExit")
DETERMINATE = {
    "CircularProgress": "degree",
    "ClippedFilledCircularProgress": "animatedValue",
    "StyledProgressBar": "value",
}
for name, prop in DETERMINATE.items():
    body = src(name)
    m = re.search(rf"Behavior on {prop} \{{(.*?)\n    \}}", body, re.S)
    check(m, f"{name} must animate `{prop}` -- a progress jump with no motion is a glitch")
    if not m:
        continue
    check(any(s in m.group(1) for s in NO_OVERSHOOT),
          f"{name}'s `{prop}` must run on one of {NO_OVERSHOOT} -- AOSP's "
          "ProgressAnimationSpec is DampingRatioNoBouncy and a spatial spec clips past 1")
    check(not re.search(r"\bduration:\s*\d", m.group(1)),
          f"{name} must not hand a literal duration to `{prop}`")

# --- 3. The indeterminate sweep is AOSP's, to the millisecond.
bar = src("StyledIndeterminateProgressBar")
CYCLE = 1750  # LinearAnimationDuration
# (property, delay, span) from ProgressIndicator.kt's First/SecondLine Head/Tail.
WINDOWS = [("firstHead", 0, 1000), ("firstTail", 250, 1000),
           ("secondHead", 650, 850), ("secondTail", 900, 850)]
check(f"cycleMs: {CYCLE}" in bar,
      f"StyledIndeterminateProgressBar's cycle must be AOSP LinearAnimationDuration ({CYCLE})")
for prop, start, span in WINDOWS:
    check(re.search(rf'prop: "{prop}";\s*startMs: {start};\s*spanMs: {span}\b', bar),
          f"{prop} must sweep for {span}ms from {start}ms (AOSP ProgressIndicator.kt)")
    check(start + span <= CYCLE,
          f"{prop}'s window runs past the {CYCLE}ms cycle -- it would stall at the edge")
# A segment is a round-capped stroke clamped inside the track (AOSP
# drawLinearIndicator), never a bare `(head - tail) * width`: with every endpoint
# on emphasizedAccel, the loop seam has both lines at zero length for ~124ms, and
# only the caps keep a dot on screen through it. Swept per ms to prove it.
check("visible: head > tail" in bar and "width: end - start + height" in bar,
      "a Segment must draw its round caps -- without them the track empties at the loop seam")


def accel(x, p1=(0.3, 0), p2=(0.8, 0.15)):
    lo, hi = 0.0, 1.0
    for _ in range(50):
        t = (lo + hi) / 2
        bx = 3 * (1 - t) ** 2 * t * p1[0] + 3 * (1 - t) * t * t * p2[0] + t ** 3
        lo, hi = (t, hi) if bx < x else (lo, t)
    t = (lo + hi) / 2
    return 3 * (1 - t) ** 2 * t * p1[1] + 3 * (1 - t) * t * t * p2[1] + t ** 3


pos = lambda ms, s, d: accel(min(max((ms - s) / d, 0), 1))
empty = [ms for ms in range(1, CYCLE) if not any(
    pos(ms, *WINDOWS[i][1:]) > pos(ms, *WINDOWS[i + 1][1:]) for i in (0, 2))]
check(not empty, f"no segment is drawn at {len(empty)} ms of the cycle, from {empty[:1]}")
check("Material.accent" not in bar,
      "Material.accent does nothing under QT_QUICK_CONTROLS_STYLE=Basic -- paint the track")
check("Appearance.animationCurves.emphasizedAccel" in bar,
      "the sweep runs on LinearIndeterminateProgressEasing, which is emphasizedAccel")

# --- 4. The loading indicator keeps AOSP's two constants and a token leap.
loading = src("MaterialLoadingIndicator")
check("duration: 4666" in loading,
      "MaterialLoadingIndicator's spin is AOSP GlobalRotationDurationMillis (4666)")
check("interval: 650" in loading,
      "its morph interval is AOSP MorphIntervalMillis (650)")
check(loading.count("Appearance.animation.elementMoveSmall.duration") == 2,
      "both leap animations run on elementMoveSmall -- they must finish inside the interval")

# --- 5. No per-frame JS path rebuild came back (DESIGN.md 8).
for name in ("SineCookie", "MaterialCookie"):
    check("FrameAnimation" not in src(name),
          f"{name} rebuilds its path in JS; a FrameAnimation makes that a per-frame cost")

for msg in fails:
    print(f"FAIL {msg}")
print(f"{'FAILED' if fails else 'ok'}: progress indicators, {len(fails)} failure(s)")
sys.exit(1 if fails else 0)
