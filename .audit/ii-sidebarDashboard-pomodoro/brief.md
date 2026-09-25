# ii-sidebarDashboard-pomodoro — brief

**Purpose.** Run one countdown or a stopwatch from the sidebar without opening an app.

**Primary action.** Start/pause. It is the one filled button on both tabs, always on the
right, always in the same place. Reset and Lap are the neutral button beside it.

**Hierarchy.** The time first (big, tabular digits), then start/pause, then the ring or the
lap list, then reset/lap. The "Click to set" hint is a caption in `colSubtext`.

**Reference.** The Android 16 Clock app (M3 Expressive). Timer: a determinate ring around
the time. Stopwatch: the time centred, dropping to the top when the first lap arrives, laps
listed newest first. Both: a full-width pair of pill buttons at the bottom, and the
play/pause pill squares its corners while running.

**Interaction.**
- *Buttons.* One `TimerButton` (a `RippleButton`, icon + label) shared by both tabs, so a
  tab switch does not move or restyle anything under the pointer. Hover/pressed/focus come
  from `colPrimary*` and `colLayer2*`. The timer's start button had no hover colour at all,
  because its hover was set to its base colour. Disabled is RippleButton's 0.4. Width is
  half the row each, not a literal 90, so "Resume" and translations fit.
- *Play/pause shape.* `rounding.full` idle, `rounding.normal` running, on RippleButton's
  own radius behaviour (`elementMoveSmall`, spatial).
- *Stopwatch readout.* Its move between centred and top ran on `elementMoveFast`, which is
  an effects curve on a spatial move (rule 3). Now `elementMove`. It is centred rather
  than pinned to the buttons' left edge, and the digits are tabular so nothing jitters.
  Centiseconds are `.CC` in `colSubtext`, as in the lap rows. The old `:<sub>CC</sub>`
  read as hours.
- *Keys.* L only records a lap on the Stopwatch tab while it runs. Before, it pushed a
  stale time from either tab, even when paused.

**Edge states.**
- *Timer idle:* full ring, "Start", reset disabled, "Click to set".
- *Timer paused:* "Resume", and the caption says "Paused".
- *Timer done:* notification, back to idle (service, unchanged).
- *Stopwatch idle:* 00:00.00 centred, "Start", reset disabled.
- *One lap:* readout moves up, one row. *Many:* the list scrolls.

**Cost.** The stopwatch refreshed from a 10ms service `Timer`: JS at 100Hz for as long as
it ran, sidebar shut or not, and the bar's and the clock popup's bindings re-ran each
time. They only show seconds. The service now ticks at 100ms. The centisecond readout
runs off a `FrameAnimation` that only runs while the stopwatch runs and its tab is
showing in an open sidebar. The ring keeps `CircularProgress`'s one layer.

**Delete.** The error-red Reset. Reset is not destructive, and a disabled one was a dark
red block. The per-button literal 35×90 sizes and the duplicated colour triplets.

**Out of scope.** Pomodoro focus/break cycles; this is one countdown. A paused state that
survives a shell restart, which neither tab has. The bar's `TimerWidget` and the clock
popup. The rail's "Timer" tab name duplicating the inner tab.
