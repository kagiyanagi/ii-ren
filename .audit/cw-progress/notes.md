# cw-progress — notes

## The knobs died for free, which the brief did not expect

`animationDuration` and `easingType` on `CircularProgress` /
`ClippedFilledCircularProgress` are the brief's "worst case of finding 3", and the
session was set up assuming caller fallout. There is none: **zero call sites set
either**, on either type, anywhere in the tree including `user_widgets/`. The only
`animationDuration` left in the shell is `TransitionImage`'s, which is cw-motion's
and legitimate. The industrialised violation was a loaded gun nobody had fired yet.

So no orchestrator edits are needed. The `## Needs a change outside this family`
section at the bottom is empty on purpose.

`fillOverflow` (both files), and `gapAngle` / `fill` on `ClippedFilledCircularProgress`,
went the same way — declared, never read by the widget, never set by a caller.
`CircularProgress.fill` is **kept**: no caller sets it either, but unlike the others
it is live code with a visible effect (the filled track variant), and deleting
behaviour nobody asked me to delete is the bigger risk. Its `radius: 9999` is now
`Appearance.rounding.full`, so the variant obeys sharp mode.

## Why determinate progress is on an *effects* spec

DESIGN.md 2.1 sorts by medium: an arc sweep is geometry, so the table says spatial,
and spatial may overshoot. That is the wrong answer here and AOSP says so out loud —
`ProgressIndicatorDefaults.ProgressAnimationSpec` in `ProgressIndicator.kt` is

    SpringSpec(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = StiffnessVeryLow,
               visibilityThreshold = 1 / 1000f)

`DampingRatioNoBouncy` is ζ 1.0. A progress indicator's geometry *is* its value, so
an overshoot is not a spring settling, it is the widget reporting a number that
never happened. All three determinate widgets now animate on `elementMoveFast`
(200ms, `expressiveEffects`, ζ 1.0) — `StyledProgressBar` was on `elementMoveEnter`,
default spatial, and did overshoot mid-range.

Measured in a `FloatingWindow` harness, 0 → 1 in one step, 56 frames over 900ms:

    117:0.000 138:0.191 171:0.587 206:0.905 256:0.986 289:0.999 305:1.000 …

188ms of travel, monotone, max exactly `1.0000` on both circular widgets. `QQC2`
clamps `ProgressBar.value` to [from, to] anyway, so `StyledProgressBar` never showed
the overshoot as >100% — but `ClippedFilledCircularProgress` has no such clamp, and
its square-mode tip walk (`tipX`/`tipY`) runs off the end of its last segment above
1.0. The no-overshoot spec is what makes the clamp unnecessary; if anyone moves these
back to a spatial spec, clamp `animatedValue` in the same commit.

ζ 1.0 at `StiffnessVeryLow` settles in ~825ms to 2%, which is why the hand-picked
`800` was in the right neighbourhood. 200ms is the repo's nearest critically damped
token and DESIGN.md 2.4's own rule of thumb ("≤200ms for a widget"); there is no
~800ms ζ-1.0 spec in `Appearance` and inventing one would have been a token change,
which this session is not allowed to make. If a future session adds one, these three
widgets are its first callers.

## `StyledIndeterminateProgressBar` was never rendering in this shell's colours

It was three lines: `ProgressBar { indeterminate: true; Material.accent: colPrimary }`.
`shell.qml`, `settings.qml`, `welcome.qml` and `killDialog.qml` all carry
`//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic`, and under Basic the Material attached
property is inert. `/usr/lib/qt6/qml/QtQuick/Controls/Basic/ProgressBar.qml`:

    contentItem: ProgressBarImpl { … color: control.palette.dark }
    background:  Rectangle { … color: control.palette.midlight }

Qt's greys, Qt's block animation, nothing from `Appearance` and nothing from M3 —
in two dialogs (Wi-Fi, Bluetooth), the wallpaper selector and the waffle wrapper.
`check-design.py` cannot see this: the violation is in Qt's file, not ours.

Rewritten as the M3 two-segment sweep, transcribed from `ProgressIndicator.kt`:
`LinearAnimationDuration` 1750, `FirstLineHead` 1000 at 0, `FirstLineTail` 1000 at
250, `SecondLineHead` 850 at 650, `SecondLineTail` 850 at 900, every endpoint on
`LinearIndeterminateProgressEasing` = `EasingEmphasizedAccelerateCubicBezier` =
`Appearance.animationCurves.emphasizedAccel`. Each segment spans [tail, head]; the
head leads, so it grows out of the left edge and is swallowed by the right.

Measured over 3.5s at ~62fps: the cycle repeats at exactly 1750ms, `minX` 0,
`maxWidth` 200 of 200, `maxRight` 200 — nothing draws outside the track.

**Deliberately not transcribed:** AOSP's `gapSize`, which paints the track in
*fragments* with a 4dp hole either side of each segment, and the stop indicator
(determinate only). A full-width track under the segments is the pre-`gapSize` M3
rendering and is ~25 lines shorter. If the gap is ever wanted, it is
`ProgressIndicator.kt:288–333`.

`background: null` moved the implicit size onto the `contentItem`, so
`WIndeterminateProgressBar`'s own `background: null` is now a redundant no-op rather
than a thing that would zero the implicit width. Both its call sites are
`Layout.fillWidth` anyway. No caller edit needed.

## `MaterialLoadingIndicator`'s three hand fits had real AOSP values waiting

`LoadingIndicator.kt`: `GlobalRotationDurationMillis` 4666 (was 12000, 2.6× too
slow), `MorphIntervalMillis` 650 (was 800), morph spring `dampingRatio = 0.6f,
stiffness = 200f`. ζ 0.6 is the fast-spatial scheme's damping, so `elementMoveSmall`
is the token that carries that shape, and both leap animations run on it.

The 750ms zoom pulse against a 650ms interval would have been **cut off mid-shrink**
and snapped back to the base size every cycle — the bug the interval change would
have introduced if the pulse had been left alone. Measured over 3s: `maxZoom 1.000`,
3 restarts, **0 cut off**; spin 231.5° in 3000ms, which is 3000/4666 × 360 to the
decimal.

## `constantlyRotate` was DESIGN.md 8's worst case, for nobody

`SineCookie.constantlyRotate` drove a `FrameAnimation` that incremented
`shapeRotation` every frame, which re-entered the `PathPolyline` binding and rebuilt
**361 `Qt.point`s in JS, at 60Hz, forever**. Zero callers — `CookieClock` spins the
*container* with a `RotationAnimation on rotation`, which is a transform and free,
and the config key of the same name feeds that, not this. Deleted, along with
`shapeRotation` and the `Loader`. `tools/check-progress-indicators.py` asserts no
`FrameAnimation` comes back into either cookie.

## Two Canvases were painting stale colours

Neither `Graph` nor `DashedBorder` requested a repaint when its `color` changed, and
a `Canvas` repaints on request only. `Graph.color` defaults to
`Appearance.colors.colPrimary` and every caller binds a theme colour, so the resource
graphs got away with it — their `values` change constantly and `onValuesChanged`
repaints. `BatteryUsageChart` does not: static `chartValues`, so it kept painting the
old palette across a wallpaper theme change until the settings app restarted.
`points` has the same problem behind a config option. Fixed at the widget, not the
three call sites.

## `ClippedFilledCircularProgress` paid for two offscreen surfaces to show one

Both source rectangles carried `layer.enabled: true` permanently and each had its own
`OpacityMask`, gated on `sharpMode` with `visible:`. An invisible item with
`layer.enabled` still renders its layer — that is the whole offscreen-source idiom —
so every instance held two FBOs to draw one, and the bar runs up to five of them
(two `Resource`, `Media`, plus the vertical variants). Now one `OpacityMask` whose
`source` switches, and each rectangle's layer follows the mode. Both branches grabbed
and verified: round with the glyphs punched out, square with the pie wedge.

## `StyledProgressBar` had a knob it ignored

`waveAmplitudeMultiplier` was declared, given a correct `Behavior`, and then the
`WavyLine` hard-coded `root.wavy ? 0.5 : 0` — the same value, so the knob and its
animation were dead. The fill reads the property now; the default is unchanged, so no
caller sees a difference. `waveFps` was dead outright (the `WavyLine` port moved the
drift into the shader) and is gone; `StyledSlider` has its own copy, which is
cw-inputs' to look at.

## Checked and deliberately left alone

- **`WaveVisualizer` / `RadialWaveVisualizer` (§8 budget).** Already done properly by
  an earlier session: a 30fps leading-edge update gate that stops itself when the
  audio does, one layer + one `MultiEffect` each, and `RadialWave` gates its layer on
  `waveBlur > 0`. Neither sits in a repeated delegate — `MediaWidget`, `DockMediaWidget`
  and `PlayerControl` are one instance apiece (per player, so ≤ 3). Nothing to fix.
- **`WavyLine`.** Its `duration: Math.round(2 * Math.PI * 400)` is derived from the
  `Date.now() / 400` drift of the Canvas it replaced and is documented as ambient
  motion, not a transition. Correct as-is.
- **`MaterialCookie`.** No motion, no literals, no states. Nothing owed.
- **`ClippedProgressBar` has no value animation** and did not get one. Its only caller
  is `CustomBatteryMeter` style 14 (cw-battery, lane 2), a battery percentage ticks
  1% at a time, and adding motion to a widget mid-audit by another family is how two
  sessions contradict each other. If cw-battery wants it, it is one `Behavior on value`
  on `elementMoveFast`, same as the other three.
- **`ClippedProgressBar` runs two `OpacityMask`s** (the pill, and the inverted glyph
  fill). That is two effects in one widget against §8's one, but they do two different
  jobs, the file explains why, and there is one instance of it on screen. Left.

## §9: indeterminate only where the duration is unknown

Audited all four call sites. Bluetooth discovery and Wi-Fi scanning are genuinely
unbounded. `WallpaperSelectorContent` shows the spinner only while
`value == 0` / `colorCacheProgress === 0` and swaps to a determinate bar once the
first tick arrives, which is the correct pattern. `WIndeterminateProgressBar` is a
pass-through. Nothing to convert — the determinate form (`StyledProgressBar`) already
exists and the callers already reach for it when they can.

## Tried and rejected

- **Clamping `animatedValue` to [0, 1] and keeping a spatial spec.** Would have let
  the square-mode tip walk survive an overshoot, but the overshoot is the thing AOSP
  says not to have, and the no-overshoot spec deletes the need for the clamp. Fewer
  lines and the right behaviour, rather than a guard around the wrong one.
- **`duration: 800` with an AOSP citation** for the circular widgets. 800 is on
  `MotionTokens`' official ladder and is ~the settling time of `StiffnessVeryLow`, so
  it is *legal* — but the cw-scaffolding commit already flagged "a spatial duration
  wearing an effects curve" as a thing this repo does wrong, and a cited literal in
  a shared widget is exactly the shape this family was sent to delete.
- **Transcribing AOSP's `gapSize` track fragments** into the indeterminate bar. See
  above; 25 lines for a 4dp hole.
- **Deleting `CircularProgress.fill`.** Zero callers, but live and visible. See above.
- **Qualifying the pre-existing `Unqualified access` warnings** in `CircularProgress`
  (an outer id inside a `Loader` `sourceComponent`, which wants
  `pragma ComponentBehavior: Bound`, not a `root.` prefix) and `ClippedProgressBar`.
  Not this family's work and the pragma changes `Loader` scoping.

## For the next session

- The harness does **not** have to go in `dots/`. A directory in the scratchpad with
  symlinks to the config root's entries (`modules`, `services`, `panelFamilies`,
  `GlobalStates.qml`, `assets`, `defaults`, `scripts`, `translations`, `user_widgets`)
  makes `qs -p <scratch>/probe.qml` resolve `qs.*` with nothing written into the repo.
  Symlinking only `modules` + `services` is not enough: `services/AlarmService.qml`
  does `import qs`, so the root itself has to be the config dir.
- A widget copied into that harness dir to override one property loses the
  `qs.modules.common.widgets` import that its own directory gave it implicitly. Add it
  back or `StyledText is not a type`.
- `Appearance.rounding.full` is `9999 * scale` and `scale` is 0 in sharp mode, so
  swapping a literal `9999` for it is not a no-op — it is the sharp-mode fix.
- `check-design.py`'s `cited()` only looks at the line and the **two** above it. An
  AOSP citation three lines up does not suppress; put it directly above the number.

## Needs a change outside this family

Nothing. No caller of any widget in this family needs an edit: the two removed knobs
had no call sites, the three removed dead properties had no readers, and
`WIndeterminateProgressBar`'s now-redundant `background: null` is harmless.
