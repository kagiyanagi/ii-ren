# ii-sidebarDashboard-pomodoro — notes

**Opening it.** `qs -c ii ipc call sidebarRight open`, then the Timer rail button in the
bottom group (the bottom of the three, at about `1522,898` on this 1920x1080 screen). The
group remembers its tab in `Persistent.states.sidebar.bottomGroup.tab`, so put it back
afterwards; it was To Do (1) on this machine. The inner Timer/Stopwatch tab bar is at
`y≈678`. `hyprctl dispatch 'hl.dsp.cursor.move({ x = …, y = … })'` then
`ydotool click 0xC0` drove every shot. `shot-before-stopwatch.png` is the other tab.

**The stopwatch start overflowed int, and it did not show.** `Persistent...stopwatch.start`
holds 10ms ticks since the epoch, about 1.8e11, in a QML `int`. It was stored as
`-1389272339`. It worked only because `stopwatchTime` is an int too, so the wrapped start
and the wrapped difference cancel mod 2^32. The new readout computes in JS doubles, which
does not cancel, so the start is `real` now. A stopwatch that was *running* across this
commit reads a wrapped start once and shows garbage until Reset. Nothing else is affected:
Resume writes a fresh start. The pomodoro start is in seconds and fits in an int until 2038.

**Cost.** The service stopwatch `Timer` went from 10ms to 100ms. With
`keepRightSidebarLoaded` on, which is the default, the old one ran JS 100 times a second
for as long as the stopwatch ran, and it also re-ran the bar's and the clock popup's
bindings. Pause and Lap now sample before they store, so they are exact. The sidebar's
centiseconds come from a `FrameAnimation` gated on running, `sidebarRightOpen` and
`SwipeView.isCurrentItem`. `tools/check-pomodoro.py` pins all of that. It was
mutation-tested against a 10ms interval and against a lap that does not sample first.

**Rejected.** `RippleButtonWithIcon` for the buttons. It left-aligns its content and fixes
35px, and in a half-width pill that puts the icon on the left edge. `TimerButton` wraps
`RippleButton` directly instead. The play pill's round radius is
`Math.min(rounding.full, implicitHeight / 2)`, not `height / 2`. `height` is 0 until the
layout polishes, so RippleButton's radius Behavior would animate the pill from square on
every load, and `height / 2` also ignores sharp mode. `rounding.full` itself is 9999, so
animating from it to `small` would sit clamped and then snap at the very end.

**For the cohesion pass (motion).**
- The stopwatch readout moves from centred to the top on the first lap, and back on Reset.
  That move is now `elementMove` (spatial, slight overshoot). It used to be
  `elementMoveFast`, an effects curve.
- The play/pause pill squares to `rounding.small` while running and rounds again on pause,
  on RippleButton's `elementMoveSmall`. Check that it is not too subtle at 40px.
