# ii-desktopMenu — notes

Ran **lane 1**, not the lane 2 the queue row said. The surface turned out to be
hiding a wrong pivot and a dead file behind a layout that already looked right,
and deciding what to do about either is not mechanical follow-through.

## What was measured, not assumed

- **The pivot was wrong down a 160px band of every screen, not at one pixel.**
  `leftAligned: x >= cursorX` asks the clamp which side it landed on, not which
  corner is nearest the cursor. The two agree until the card is shifted back
  inside the screen — and from the first pixel of that shift until the cursor
  passes the card's own midpoint, the menu grows out of the far corner. Swept in
  `check-desktop-menu.py`: 159 wrong positions on a single 1920-wide sweep with a
  420-tall card, and the same again along the bottom. `x <= x + width / 2` is
  both shorter and continuous.
- **The one-item strip is the live state on this machine.**
  `Wallpapers.directory` defaults to `~/Pictures/Wallpapers`, which does not
  exist here — the user's wallpapers are in `~/Pictures/Wallpapers-Custom` — so
  `shuffledWallpapers` returns exactly `[current]` and the strip renders one tile
  beside 160px of empty card. `shot-before.png` is that. The strip now needs two
  entries before it earns its 132dp.
- **The keyboard worked, end to end, after the change and not before.** With the
  menu open from `ipc call desktopMenu toggle`: `wtype -k Down` twice highlights
  the second row (the focus state only appears on a Tab-reason focus, so a
  mouse-opened menu still opens with nothing highlighted), `Return` on *Drop
  shelf* dismissed the menu and opened the shelf, and `Escape` dismisses. Before,
  every one of those keys did the same thing — dismiss.
- **`WidgetActions.qml` was reached by nothing.** Not by url, not by type, not by
  the file that sits next to it. Its rows had been copied into `DesktopMenu.qml`
  and the file was left behind. Deleted.

## Driving this surface

Easy, unlike most of the queue: `qs -c ii ipc call desktopMenu toggle` opens it
centred with no cursor involved, so none of the `ydotool` correction the
cheatsheet and clipboard-toast rows needed applies. `wtype` is enough for
everything the keyboard does. `hyprctl layers | grep desktopMenu` is the open
test.

To see the wallpaper strip at all on this machine you have to give
`~/Pictures/Wallpapers` something to list. `shot-after.png` was taken with that
folder created and filled with six symlinks into `Wallpapers-Custom`, the shell
restarted, and **the folder removed again afterwards** — check it is gone
(`ls ~/Pictures/`) if a session is cut off mid-shot.

## Left alone on purpose

- **The `OpacityMask` inside the wallpaper delegate stays.** It is in
  `check-effect-budget.py`'s `KNOWN` set as shrink-only and this row is the one
  that could have shrunk it, so: every way out costs more per tile than the one
  framebuffer it removes. `RoundCorner` is four `Shape` layers, each with its own
  `layer.enabled`. Masking the whole strip once means building a mask that
  mirrors each tile's position, which is re-deriving `ListView`'s layout from
  `contentX` by hand — and the tiles resize under an animation, so it would have
  to track that too. Dropping the mask and letting the thumbnail's square corners
  sit on the rounded tile is visible at `rounding.normal` on a 98px tile. The
  honest answer is that one FBO per visible tile, for a strip of five or six that
  only exists while a context menu is open, is the cheapest of the four.
- **`DockMenuButton` stays in `modules/ii/dock`.** The `ponytail:` comment at the
  top of the file asks for it to move to `common/widgets`, and there are now four
  callers, which is past the bar it set. Three of them are `modules/ii/dock`,
  whose queue row is still open — moving a shared widget out from under a
  surface whose own row has not run is how DESIGN rule 9 gets broken. It belongs
  to `ii-dock`.
- **`ipc call desktopMenu toggle` centres the anchor, not the menu.** The card's
  top-left lands on the screen centre, so the menu hangs down and right of it.
  Centring the card itself needs its size, which nothing knows at IPC time, and
  the fix would mean a second meaning for `desktopMenuX` — which the drop shelf
  also reads. Left as is; with the keyboard working it is no longer the only way
  to use the menu.

## For the cohesion pass

The close **retimed**: 190ms with a 60ms fade hold → `arrowPopupCloseDuration`
233ms with `arrowPopupFadeHold` 150ms, which is AOSP's `ArrowPopup.animateClose()`
and what the four bar popups, the systray menu and both combo boxes already use.
The 190/60 it replaced was typed beside the animation, not sourced. Watch that
the slower close does not drag on a menu that gets dismissed constantly — the
comment that justified the old numbers said exactly that, and it may turn out to
have been right for this surface even though it was not measured.
