# ii-sidebarDashboard-quickToggles — brief

**Purpose.** Flip the things you flip ten times a day: Wi-Fi, Bluetooth, volume,
brightness, Night Light, power profile. Then get out of the way. It is the top card of
the right sidebar, laid out on a 4-column packed grid of pages the user edits in place.

**Primary action.** A tap on a tile. Everything else is secondary: a long-press or
right-click opens the tile's dialog, a slider drag sets a level, and edit mode is behind
the pencil.

**Hierarchy.** The tiles, read as one grid inside one `colLayer1` card: on is a
`colPrimary` fill, off is `colLayer2`. Then the page dots. In edit mode it goes grid, then
the page toolbar, then the drawer of unused tiles at half strength.

**Reference.** Android 16's Quick Settings panel and its edit mode. The shell *is* this
surface's reference: DESIGN.md §9 names the `androidStyle` toggles as the quick-settings
tile recipe. So this row repairs it and does not redesign it. The tile shapes, the
three-way sliders, the gamma-into-brightness slider and the earbud art are the owner's,
and stay.

**What is wrong, measured.**
- **The grid is off-centre.** `baseCellWidth` takes `spacing * columns` off the width
  where a 4-column row has three gaps. Every row stops 12px short of the card's right
  edge and 6px from its left.
- **One tap on a three-way slider breaks the panel for the session.** Its press
  walked every ancestor, set `interactive = false` on anything that had the property,
  and then set `true` on release. That assignment destroys `flickable.interactive:
  !root.editMode` and `panelScroll.interactive: contentHeight > height`. After it, a
  vertical drag on the panel's background rubber-bands the whole grid (measured). In
  edit mode, a drag between tiles turns the page. The `MouseArea` already has
  `preventStealing`, which is the documented way to keep a Flickable off a drag.
- **Bluetooth never looks on unless something is connected.** The disconnected
  icon was `colLayer3` when on and `colSurfaceContainerLow` when off: two greys. The
  Wi-Fi tile beside it is `colPrimary` whenever the radio is on. The Bluetooth tile
  follows `toggled` now, like every other tile.
- **The 2x2 Bluetooth tile could not turn Bluetooth off.** A tap anywhere opened the
  dialog, because its icon was not a separate target. The tall and 2x2 layouts now
  share one icon.
- **State films at invented alphas.** The icon hover and press films were
  `transparentize(…, 0.95 / 0.88)`, which is 0.05 and 0.12. The tokens are 0.08 and
  0.10, and the clover and cookie icons already use them. The 2x2 Wi-Fi tile still
  had the square `Rectangle` film over a cookie, reading a `radius` that
  `MaterialShape` does not have. That is decision 18's bug, in the one copy it
  missed.
- **Spatial motion on an effects spec.** A tile moving or resizing in edit mode, and the
  three-way knob sliding, ran on `elementMoveFast`, which is the colour/opacity spec. The
  page snap ran on `Easing.OutQuint` at a spatial token's duration, a curve nothing in
  `Appearance` names.
- **The panel's height animated twice.** `flickableContainer` animates its height, and
  the panel's `implicitHeight`, which is derived from it, had a second `Behavior`. That
  one restarts every frame towards a target that is itself moving.
- **Edit-mode toolbar corners.** It is a connected group whose ends were fixed, so the
  `+` button kept square outer corners whenever its neighbour was hidden: on one page,
  and on the last page.
- **A click removes a tile, and nothing on the tile says so.** Unused tiles carry a `+`
  badge, and used tiles carry nothing.

**Interaction.**
- Tile geometry (edit-mode reflow and resize) on `elementMoveSmall`. It is reversible,
  because the preview reflows on every pointer move. The three-way knob uses
  `elementMoveSmall` too. The page snap is a panel-width move, so it is curve-based
  (§2.4): `emphasizedDecel` at `elementMoveSmall`'s 350ms. A spatial curve would
  overshoot past the last page into blank space.
- The three-way knob gets hover and press states: `colPrimaryHover` and
  `colPrimaryActive`, the token pair.
- Icon hover and press films use `StateOverlay` where the container is a `Rectangle`,
  and the 0.08 / 0.10 mix where it is a `MaterialShape`, which cannot take an overlay.
- A dragged tile lifts (scale 1.05) and does not also fade (§3.6).
- Page dots keep their look. They get one 32px-tall target over the whole row that
  turns to the nearest dot. Per-dot areas could be no wider than a dot plus half
  the gap on each side.
- The edit badge fades on `elementMoveFast` while a tile is dragged or resized.

**Edge states.**
- *One page*: no dots, and the toolbar is the page label and a pill-ended `+`.
- *Bluetooth off / no adapter*: the icon is `colLayer3`, or the whole tile is at 0.4.
- *Bluetooth on, nothing connected*: a `colPrimary` icon with "No devices".
- *Empty drawer* (every type placed): the drawer has zero height, as before.

**Cost.** Nothing new. The media tile keeps its blur plus mask (two layers, one tile,
placed at most once). The connected earbud art keeps its four `ColorOverlay`s: two
colours per bud, drawn only while a device is connected. Both are noted and left.

**Delete.** ThreeWaySlider's ancestor walk, all three copies of it. The duplicated
device properties and icon trees in `AndroidBluetoothToggle` (one component now). The
second height `Behavior`. The film `Loader`s.

**Out of scope.** `classicStyle/`, which is shared with waffle's action centre and
`services/Idle.qml`. The edit controller's and the packer's logic. The media tile's text
colours on album art. `tools/p3-quick-toggles/port-toggles.sh`, which is stale: see
`notes.md`.
