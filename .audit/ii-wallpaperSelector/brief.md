# ii-wallpaperSelector — brief

**Purpose.** Pick the wallpaper: find a picture in a folder you keep them in, and set it.

**Primary action.** Click a thumbnail (or Enter on the focused one) and the wallpaper is
set. Everything else — folders, favourites, colour filter, dark/light, search — narrows
the grid or changes how the pick is applied, and must look secondary to the grid.

**Hierarchy.** 1. The thumbnail grid. 2. The floating toolbar at its foot (search is
the one field in it). 3. The rail of places on the left, the address bar above.

**Reference.** Android 16's *Wallpaper & style* picker for the tiles — the picture is the
tile, rounded, flat on the surface, no card chrome — and the M3 Expressive floating
toolbar for the actions, with a contextual toolbar for the one tile you right-clicked
(Google Photos' selection bar).

**Interaction.**

- **The surface.** It hangs from the bar, so it grows out of its **top edge**. Keybind
  and IPC open it, so intent (`GlobalStates.wallpaperSelectorOpen`) and mapping are
  separate: the `Loader` follows a latch that only the finished exit clears — the
  cheatsheet's shape, its scale and its two specs (enter `elementMove` on
  `emphasizedDecel`, exit half of it on `emphasizedAccel`), the spec assigned inside
  the binding that drives it (2.9). The layer gets `no_anim`, or Hyprland's `popin`
  runs on top of it from the centre.
- **Tiles.** The picture fills the tile at `rounding.normal`; the name sits under it and
  elides. Hover is a 0.08 film, press 0.10 (`StateOverlay`), pointing-hand cursor.
  Keyboard focus and the right-clicked tile get a `colPrimary` ring — a film alone
  vanishes over a photo. Focus only shows once the keyboard has moved it or a filter is
  typed, so a resting pointer never shows two "selected" tiles (the session-screen
  defect). The applied wallpaper's name carries a check and `colPrimary`. Folders are
  the same tile around `DirectoryIcon`.
- **Contextual and colour toolbars.** Both enter and leave on `ArrowPopupMotion`, out of
  their bottom-right corner (toward the corner they are pinned to and, for the colour
  one, the palette button that opens it). Escape clears the right-clicked tile before it
  closes the surface.

**Edge states.** Loading: a tile is `colLayer1` until its thumbnail fades in. Empty
folder, empty favourites, nothing matching the search or the colour: a `PagePlaceholder`
that says which. One item: a single tile at the grid's top-left. Error: an invalid path
typed in the address bar leaves the directory alone (it used to be applied anyway).

**Cost.** One `OpacityMask` for the whole grid, drawn from one rounded rect per visible
cell, instead of one per tile plus a shadow per tile (`check-effect-budget.py` never saw
them: the tile is its own file, the dock's blind spot). The 16ms timer that released one
tile per frame goes: `GridView` already builds only what is on screen. Kept: the panel
shadow, the three toolbars' shadows, the hovered tile's `RippleButton`.

**Delete.** The `---` rail entry (a text divider, law 11) and Documents (not where
wallpapers live). The per-tile shadow and masks. `loadTimer` / `shouldLoad`. Both
`ListModel`s, the 10ms deferral and the refresh functions — favourites and the colour
filter are bindings over arrays. The negative row spacing.

**Also fixed in `services/Wallpapers.qml`.** `setDirectory` assigned every path, valid or
not, before checking it. Paths were pasted into `bash -c` (a folder with a space in its
name got no thumbnails; a `"` ran code), and so was the browser's download URL, into a
download dir read from a config key that does not exist.

**Out of scope.** `AddressBar` / `AddressBreadcrumb`, `NavigationRailTabArray`,
`ThumbnailImage` (shared). The wallpaper-browser extension's own service — it is not
installed here, so its mode is kept working but not redesigned. The panel radius formula.
