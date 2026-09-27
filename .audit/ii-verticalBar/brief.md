# ii-verticalBar — brief

Read `.audit/ii-bar/brief.md` first: the vertical bar is the same surface family,
turned 90°. This row owns the nine files in `modules/ii/verticalBar/` and nothing
else. `BarComponent`, `BarGroup` and every popup stay frozen — they were done by
the `ii-bar-*` rows and this bar only consumes them.

**Purpose.** The bar, on a screen edge instead of the top: the same ambient status
and the same handles, stacked.

**Primary action.** None, as for the horizontal bar. The row succeeds when a user
who flips `bar.vertical` sees *the same bar* — same motion, same colours, same
options honoured — and nothing that only exists because this copy was forked
before the horizontal one was fixed.

**Hierarchy.** Top: left list. Middle: centre list, the clock at its centre.
Bottom: right list. Unchanged.

**Reference.** The horizontal bar after `ii-bar-chrome` / `ii-bar-widgets`. Where
the two differ and the vertical one is not forced by its axis, the vertical one
is wrong.

**Interaction.**

- **Auto-hide.** Ran both ways on `elementMoveFast` — an effects spec on
  position, identical in and out, the defect `ii-bar-chrome` fixed in `Bar.qml`.
  Take the same shape: `revealed` / `revealSpec` / `edgeOffset`, enter on
  `elementMoveEnter`, exit on `elementMoveExit`, the spec assigned inside the
  binding that writes the margin (§2.9). And the right-hand bar
  (`bar.bottom`) hid by `-barHeight`, the *horizontal* bar's thickness: a 46px
  bar pushed out by 40 left 6px of it on screen. It is the vertical width.
- **Background.** Honour `bar.cornerRadius` in float style, as `BarContent` does,
  and fade `border.color` with the fill.
- **Timer pill.** Two chips that `visible:`-snapped inside a pill whose height ran
  on `elementMoveFast`. Use `Revealer { vertical: true }` per chip and animate
  the gap, as `TimerWidget` does; the pill follows the Revealers, no Behavior of
  its own. Hover film fades to a transparent copy of itself, not `"transparent"`.
- **Resources.** Honour `showTemp` / `showGpu` / `showDisk`, in the horizontal
  order (cpu, ram, temp, swap, gpu, disk). Rings match the horizontal ones:
  `implicitSize` 20, `unsharpen` line, `pixelSize.normal` icon, `colPrimary`
  fading across the warning threshold on `elementMoveFast`. `showNetwork` is out
  — it needs `NetworkUsage.activeInstances` bookkeeping and no one asked.

**Edge states.** Auto-hide on, both edges. `cornerStyle` 0/1/2. No media player
(middle/right click must not throw on a null player). Timer with one chip, two,
none. Every resource switched off (the group collapses to nothing).

**Cost.** `StyledRectangularShadow` for float style stays. Each ring keeps the
`OpacityMask` `ClippedFilledCircularProgress` owns; six at most, not in a
`Repeater`.

**Delete.** `HorizontalBarSeparator` (a separator, law 11, and unused). Both
`brightnessMonitor` properties (read by nothing). `BatteryIndicator`'s five
re-exports (read by nothing — the horizontal row deleted its own). The top
scroll area's `height`/`width`/`implicitWidth`, which its four anchors override.

**Real bug beyond motion.** `Resource.qml` passed a bare `MaterialSymbol` as the
ring's mask. `OpacityMask` scales its mask to the ring, so each icon was blown up
from its glyph box to fill the ring edge to edge instead of sitting at its size.
It needs the same `implicitSize` wrapper `VerticalMedia` and the horizontal
`Resource` use.

**Out of scope.** `BarComponent` and every widget it shares between bars.
`deadPixelWorkaround`, which the horizontal bar applies and this one does not —
recorded in `notes.md`, not built. `ScrollHint`, which is written for a left/right
side.
