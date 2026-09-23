# ii-overview — notes

Lane 1, one session. Brief written in the same session (no cluster brief exists for the
loose `ii-*` rows). Gate: `tools/check-overview.py`, new.

## What the 60fps pass has to watch

This row retimed the surface's whole open/close, and no still frame shows any of it.

- **The zoom, `Overview.qml`.** `scaleAnimated` ran both directions on `elementMoveFast`
  (200ms, *effects* curve). It is now `elementMoveEnter` (500ms, default spatial) in and
  `elementMoveExit` (130ms, fast effects) out. The thing to look for is whether the
  overview and the desktop plane behind it now travel together — that register is the
  whole point, and it is the finding `ii-background-root` left here because it could not
  drive the overview. Also watch a fast `Super`-`Super`: the Behavior is explicitly
  `alwaysRunToEnd: false`, because it drives `visible` and a close held off for a 500ms
  enter leaves the layer mapped and holding the keyboard.
- **The focus ring, `OverviewWidget.qml`.** Its x/y/width/height moved from
  `elementMoveFast` to `elementMoveSmall` (350ms fast spatial) — position and size are
  spatial (2.1). Its four radii now animate too; see below.
- **The search field's width**, `SearchBar.qml`: a hand-written `duration: 300` wearing
  `elementMove`'s curve became `elementResize` (350ms). It fires on the first keystroke.

## Found while here

**The focus ring's four `Behavior on *Radius` were for a feature nobody finished.** They
were animating `radius: Appearance.rounding.normal` — a constant — so they were dead. The
reason they existed is that the ring is meant to take the corner shape of the tile it
outlines (23 at the grid's outer corners, 8 everywhere else), and that half was never
written, so the ring drew a uniform 17 that matched no tile. Written now, and the
Behaviors kept rather than deleted.

**The ring was also 4px wider than its tile**, left-aligned, so it overhung into the gap
on the right only. Nothing justified the `+ 4`; removed.

**The launcher's `OpacityMask` was masking nothing, and masking it wrong.** Its mask rect
was `width × width` — square, stretched over a card that is always taller than it is wide.
And no delegate ever reaches the card's corner arc: measured, the result rows clear it by
5.4px at the collapsed radius (28, which is what Qt clamps `rounding.verylarge` to at the
56px collapsed height) and more when expanded. Deleted outright, −2 framebuffers, no visual
change. `check-overview.py` evaluates that arithmetic, because if the row inset or the list
margins shrink the delegates start clipping with neither a gate nor a mask.

**Deleting the separator also removed a real Qt warning.** The 1px rule was a `Rectangle`
with `height: 1` inside a `GridLayout`, which qmllint reports as *"Detected height on an
item that is managed by a layout. This is undefined behavior"* — the class
`check-scaffold-containers.py` exists for. Law 11 and Qt agreed.

## Not done, and why

**`OverviewWindow`'s `layer.enabled` + `OpacityMask` stays.** One offscreen pass per open
window, inside a `Repeater`, which 8 forbids. `check-effect-budget.py` has never seen it —
that gate reads a `Repeater`/`delegate:` block *inside one file* and every overview window
is its own file, the dock's blind spot exactly. It stays because the rounding is the
thumbnail's whole silhouette, the four radii are computed per window from its distance to
each tile edge, and **`ClippingRectangle` is not cheaper**: its own source is a
`layer.enabled` mask Rectangle plus a `ShaderEffectSource` plus a `ShaderEffect` — the same
two framebuffers — and its documentation says it costs more than a `Rectangle`. So the
ceiling is stated instead, at one per delegate file, the way `check-dock.py` states the
dock's.

**`ScreencopyView { live: true }` on every window is not the cost it looks like.** Read
quickshell's `view.cpp`: the capture is requested from `updatePaintNode`, so an item that
is not painted does not re-capture. A closed overview and a grid hidden behind search
results both cost nothing. Checked before "fixing" it.

**`ScrollingOverviewWidget.qml` took only the shared fixes.** The shipped Hyprland layout
is not `scrolling`, so nothing in this session could see it render.

**The layout was left alone.** The grid geometry and every `Config.options.overview.*` knob
that feeds it are the user's. The assembly hangs from the top of the screen with a void
below on purpose: that void is where the results list expands into.

## Two dead ends, so the next session does not repeat them

**`sed -i` does not reach a running quickshell.** It replaces the inode, which breaks the
file watch, so a live edit appears to do nothing. Restart (`tools/audit/smoke.sh`) after
any scripted edit you want to see.

**`ydotool mousemove -a` does not land where you ask on this machine** — tried at three
positions, with `accel_profile flat` and `sensitivity 0`, and it went to 1918,901 every
time. `hyprctl dispatch 'hl.dsp.cursor.move({ x = …, y = … })'` positions the pointer
exactly.

**But a warp alone does not produce a hover.** `cursor.move` puts the pointer inside the
surface and a click there lands, but no `wl_pointer.motion` reaches the client, so Qt's
`containsMouse` never updates and every hover state reads as absent. The tile measured
identical to its neighbour and the state layer looked broken; it was not. Warp to a few
pixels off the target, then `ydotool mousemove -x 5 -y 5` to generate a real motion event.
Measured after that: hovered tile (40,42,35) against (26,28,22), which is the 0.08 token
over `colSurfaceContainerLow` to within a unit, and identical to forcing `hover: true`.

## How to open it

`qs -c ii ipc call search open` / `close`, or `Super`. `toggle`, `workspacesToggle`,
`clipboardToggle` and `toggleReleaseInterrupt` are on the same `search` IPC target.

The empty-results state is **unreachable in the shipped config** —
`search.prefix.showDefaultActionsWithoutPrefix` synthesises Command / Math result / Web
search for any string, including behind a prefix. To look at it, flip the placeholder's
`active:` to `root.showResults` and restart; it was verified that way and reverted.

## Follow-up: the results list blinked (reported after the row landed)

Reported as "the search result appears, then it blinks 2 or 3 times", pointing at the
green highlight behind the focused row. Measured with a `grim` burst on a 486x46 crop
of the current row: the fill drops from (67.8, 91.4, 31.9) to (45.1, 49.5, 36.6) about
250ms after the last keystroke and takes ~240ms to come back. Three causes, all of them
one mechanism.

**Assigning `model:` rebuilds everything.** `QQmlDelegateModel::setModel` emits a remove
of the old count and then an insert of the new one, so handing the list a new JS array
destroys every delegate and builds them all again — logged it: `delegate-` x11 followed
by `delegate+` x11, every time. The rows come back saying the same thing in the same
places, so a still frame shows nothing; what shows is whatever motion hangs off those
two signals, and the highlight, which the new current row has to fade in from nothing
because it is built before `currentIndex` is put back.

1. **`ListView` -> `StyledListView` in `fc341d92f` was mine.** The old plain `ListView`
   had no transitions, so the churn was invisible. The shared list slides a leaving row
   off to the right and scales an arriving one up from zero, which turned every rebuild
   into a flash. `animateAppearance: false`, same as the bluetooth, wifi and mixer
   lists — the set is replaced, not added to.
2. **The 200ms debounce bought nothing.** It handed over the first 15 results and then
   assigned the full set again. A `ListView` instantiates what fits its viewport — 11
   rows here — whether `count` is 15 or 57, so the slice limited nothing and the second
   assignment was a rebuild carrying content the first had already carried. Deleted.
3. **`qalc` answers every string.** `fire` is 0, `firefox` is 0 B, `code` is code(); it
   reports that it did not understand in its *exit code*, which `SplitParser` cannot
   see. So a Math result row sat under every ordinary app search, and because qalc lands
   a quarter second behind the rows, writing it rebuilt the model once more right after
   the list had settled. `StdioCollector` + `onExited` gated on `exitCode === 0` now,
   and the row is only pushed when there is a result. This is the blink that was left
   after 1 and 2.

Measured after: 4 keystrokes, 4 rebuilds, and the green channel of the current row is
flat to 0.00 over 2.3s once the query lands.

**The action buttons were 8px above centre.** `Layout.alignment: Qt.AlignTop`, from this
row's own fix — the row layout is `buttonVerticalPadding * 2` taller than its tallest
child, so the top pins them half that above the name and the verb beside them. The
negative margin it replaced had put them the same distance *below*. Measured on the
Firefox row: icons centre 149.5, "Open" 149.0, row centre 148.0.

## Found and left alone: the desktop-entry scan

For the first ~17 seconds after `qs` starts, `DesktopEntries.applications` emits
`valuesChanged` several hundred times as it populates (733 in one run). `AppSearch.list`
and `preppedNames` are bindings over it, so each emission re-prepares the whole fuzzy
index and re-runs `LauncherSearch.results`, which rebuilds every launcher row. Opening
the launcher inside that window strobes and pins `qs` at ~80% CPU; it stops dead once
the scan finishes, and none of the fixes above touch it. It is the kind of thing that
would be a row of its own — `AppSearch` is read by the bar, the dock, the OSD, the
volume mixer and both panel families, so coalescing its index is a shared-service change
(9), not a launcher one. Worth knowing when reading a CPU trace taken right after a
restart: the shell looks like it is in an infinite loop, and it is not.
