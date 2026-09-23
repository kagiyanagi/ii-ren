# ii-screenCorners — notes

Ran lane 1, not 2. The row was four behaviour bugs and no layout, and every one of them
needed the shell driven to prove.

## What was measured, and how

- **Several monitors.** `hyprctl output create headless CORNERPROBE`, then
  `hyprctl layers -j`, then `hyprctl output remove CORNERPROBE`. Before: the bar went to the
  new output, and all eight corner layers stayed on eDP-1. After: four on each, at each
  output's own coordinates. `grim -o CORNERPROBE` works on a headless output, and that is
  what the two shots are: 40px crops of each corner of both outputs at 4x. Removing the
  output logs `TypeError: Cannot read property 'name' of null` from `Background.qml:46`.
  That one is pre-existing. The old corner code logged the same from its own workspace
  filter; the new one uses `?.` and does not.
- **Rounding modes.** Flip `appearance.fakeScreenRounding` in the live config and count
  `quickshell:screenCorners` layers. Before: zero in modes 0 and 3, so the enabled hot
  corner did not exist. After: the two top hot corners. Bottom corners correctly stay
  unmapped, since they have no rounding and no hot corner.
- **The edge trigger** (`clicklessCornerEnd`, on in the shipped config), with a
  `console.info` probe and ydotool slides up the right edge:
  - Arrival: one open at y≈4.6 on the old code and on the new. After that, the dashboard's
    focus grab takes the pointer, so the old per-motion repeats never showed on this path.
    They need a sidebar that takes no grab, and a pinned policies sidebar is one: it calls
    `GlobalFocusGrab.removeDismissable` when pinned. **That case is unmeasured**, because
    pinning needs the pin button and re-tiles the user's windows. The rising edge covers
    it either way.
  - **Close with the pointer resting in the corner:** the sidebar reopened at once, on
    **both** old and new code (a second `toggle` at y≈1.9, about 20ms after the IPC
    close). The grab letting go re-sends the enter, and the enter reads as an arrival.
    Fixed with the guard, and measured on the final build: it stays closed, a nudge
    inside the zone does nothing, and leaving the band and coming back opens it again.
  - **Tried and rejected: joining `GlobalFocusGrab`'s persistent set.** The corner then
    sees the pointer while the sidebar is open, but the grab changing on close still
    re-sends leave and enter, and the sidebar still reopened (measured).
  - **Leaving fullscreen with the pointer parked in the corner** (found by the
    design-check). I used a throwaway `kitty --class cornerprobe` on workspace 9,
    fullscreened with `hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })`.
    In modes 1 and 2, on old code and new, the sidebar did **not** open on exit: Hyprland
    sends no enter until the pointer moves. The first 1px nudge that stays in the zone does
    open it. That enter is indistinguishable from a real arrival up the side edge, which
    also enters straight into the zone. So starting the guard when `hotCorner` turns on,
    as the review proposed, would not help, and it was **not** done. Only a direction test
    could tell the two apart, and that needs a second event, which loses the approaches
    that cross the band in one.

## Traps

- **The live config is not the repo's.** Live `fakeScreenRounding` is **1**, and the
  `dots/` default is 2. I restored it to 2 from the repo copy, caught that with a JSON
  diff against a backup, and put 1 back. Back up `~/.config/illogical-impulse/config.json`
  first and diff against the backup, never against `dots/`.
- **The running shell stopped hot-reloading partway through this row.** After the Write
  tool's save at 23:48, none of my later edits (`sed -i`, `cp`, a `>` redirect, an in-place
  Python write) reached it. There was no `Reloading configuration` line, so an "old code"
  run silently ran the new code. I did not pin down why. Before trusting a live result,
  grep `Reloading` in `/run/user/1000/quickshell/by-id/<id>/log.log`; `qs log` lags behind
  that file. `tools/audit/smoke.sh` restarts the shell and is the reliable way to load a
  change.
- `hyprctl cursorpos` never reports x above 1918 on this 1920-wide panel. That last
  column is the one `interactions.deadPixelWorkaround` exists for, and the right-hand zone
  (`mouseX >= width - 2`) is only reachable because of that tolerance. Keep it.
- Relative `ydotool mousemove` is about 0.5px per unit here, so `-y -2` moves about 1px.
  The `-a` form jumps through (0,0), which is inside the top-left hot corner. It is
  harmless only because y=0 is outside the zone (`mouseY > offset`).
- The dashboard's layer being mapped is a faithful open/closed signal:
  `visible: GlobalStates.sidebarRightOpen`, with no latch.

## Left alone on purpose

- **Which panel a corner opens under `sidebar.position`.** The mapping is always
  left→policies and right→dashboard, so under `inverted` the top-left corner opens a panel
  on the right. The bar's side click areas (`BarContent.qml` 108/262,
  `VerticalBarContent.qml` 83/227) do exactly the same, and changing only the corner would
  split two ways of opening one panel. Under `left`/`right` both panels share a side, and
  the far corner has no right answer. A row that touches sidebar position should change
  all five sites together; the corner's is `setSidebarOpen`.
- **The vertical offset is one row out between top and bottom.** Top fires at
  `mouseY > offset`, bottom at `mouseY < height - offset`. So offset 0 leaves the absolute
  corner row out at the top and keeps it at the bottom, despite the label "at absolute
  corner". Kept exactly: people tune it by feel, and it is one row.
- **The hot strips sit on the bar's top edge.** With the shipped config, the 250x5 strips
  cover the top 5px of the bar's outer 250px on each side, on the Overlay layer. A click
  thrown to the top edge on a bar item there toggles a sidebar instead of reaching the
  item. The outermost items are the two sidebar buttons, which do the same thing, so it
  mostly agrees; tray icons and the clock inside those 250px do not. This belongs to
  whoever owns the `cornerOpen` defaults or the bar layout, not this surface.
- **A fast approach can skip the edge trigger.** With the shipped 5px band and offset 1,
  the zone is three rows. A pointer moving 3px or more per event crosses it in one event
  or none. The old handler had the same ceiling, and no binding can see an event that
  never arrives.
- **No shell-side motion on the fullscreen hide.** See the brief. The map and unmap
  already animate on Hyprland's `popin 120%` layer rule (`hyprland/rules.lua:140`), which
  I did not measure. The cohesion pass should look at it once at 60fps: a 120% pop on a
  23px black corner is the only motion this surface has.
- **`RoundCorner`'s `layer.enabled`.** It is a shared widget with 16 callers. The Shape
  already uses `CurveRenderer`, which antialiases on its own, so the layer is probably pure
  cost. That is a `cw-*` revisit, measured across every caller. Here the content is
  static and drawn once.
- In modes 0 and 3 the top windows are 250x23 with a 250x5 mask, because they take the
  hidden corner's implicit size. They are transparent and click-through, so not worth a
  ternary.

## Vision step

Skipped agy. The shots are eight 40px crops and the claim is binary (rounded or square,
per corner), so I read them directly.
