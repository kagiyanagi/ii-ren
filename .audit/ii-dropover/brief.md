# ii-dropover — brief

**Purpose.** Somewhere to put files mid-drag. A move that spans two folders, two
workspaces or two applications does not have to be one uninterrupted gesture: drop onto the
desktop, go find the target, drag back out.

**Primary action.** Dragging a tile back out. The tiles are the surface; everything else is
chrome. Today they are a 108px band under a centred "4 items" label and above three
equal-width buttons, which is the opposite ranking.

**Hierarchy.**

1. The tile strip. Biggest thing on the card, and the only thing you grab.
2. The count. It is what tells you whether you have finished collecting, so it goes in the
   header beside the name rather than floating under the strip as its own centred line.
3. **Copy** — secondary container fill, the one filled control on the card.
4. **Clear** — text button. **Close** — icon button in the header, not a third equal peer.

**Reference.** Launcher3 `ArrowPopup` for the motion and the corner pivot, and Android 16's
clipboard overlay for the posture: a transient floating surface that appears where you acted
and must not take the screen away from the app behind it.

**Interaction.**

- Enter and exit: `ArrowPopupMotion`, which is the composite decision 14 extracted. The
  caller owns only the `transformOrigin` and the resting `scale`/`opacity`.
- Origin: the corner of the card nearest the drop point, from `DesktopMenu`'s arithmetic —
  compare the *drop point* against the card's midpoint, never the clamp's result. That is
  the bug `ii-desktopMenu` shipped and then fixed, and the same shape produces it here.
- Placement: top-left corner at the drop point, slid back inside the screen by `gutter`
  (8, DESIGN 5.3). The card grows downward as items land, so the pivot corner stays put.
- Card resize as items come and go: `elementResize` — size is spatial (DESIGN 3). It is on
  `elementMoveFast` today, which is an effects spec.
- Tile: `StateOverlay` with hover, press and drag bound. Drag is the 0.16 layer, on the one
  tile whose file is in flight. The tile has no feedback of any kind today.
- Removing one item is middle-click, which nothing announces. A close chip fades in on
  hover on `elementMoveFast`; middle-click stays.
- Escape closes, with `WlrKeyboardFocus.OnDemand`. **Not `Exclusive`**, which is what
  `DesktopMenu` needed: this surface exists to be used while another window holds the
  keyboard, so it takes focus when clicked and hands it straight back.
- **No scrim and no outside-click dismiss** — a deliberate departure from the popup recipe
  (DESIGN 9). The mask leaves everything but the card click-through on purpose, because the
  window you are dragging into is behind it.

**Edge states.**

- *Empty* — reachable from `ipc call dropShelf toggle` and from the desktop menu. Today:
  a blank 108px band and "0 items". Gets a `PagePlaceholder` in the strip, and Copy and
  Clear go disabled (`opacity: 0.4`, DESIGN 6).
- *One item* — no special case; the strip is the same height whatever it holds, so the card
  does not jump between one and none.
- *Not an image* — document icon plus the filename, elided in the middle. Already correct.
- *File removed underneath us* — `StyledImage` falls back to the same document tile rather
  than an empty frame.
- *Drag in flight* — `DropShelf` already refuses every mutation while `dragActive`.
  The surface must not be destroyed either: closing while a drag is out frees the mime data
  the compositor is still reading.

**Cost.** One `StyledRectangularShadow` on the card, kept, and nothing else. It gains the
`scale`/`transformOrigin`/`opacity` mirroring `DesktopMenu` needed, or it sits full size
around a card that is scaling. Tiles stay effect-free: `StateOverlay` is `Rectangle`s and
`StyledImage` is a plain `Image`, so a 30-item shelf adds no offscreen passes.

**Delete.**

- The centred `"%1 items"` line — it moves into the header.
- `Close` as a third full-width `RippleButton`.
- The literal `-30` above-the-cursor offset, `gutter: 20`, `+ 24`, the tile's `margins: 2`.
- `visible: GlobalStates.dropShelfOpen`, which merges intent with mapping and is why there
  is no exit animation to write. Held open past the flip by a `closing` flag, as in
  `DesktopMenu`.

**Fix, not design.** `Background.qml` passes `mapToGlobal` coordinates and `DesktopMenu.qml`
passes screen-local ones into the same two globals, and the panel picks its screen from a
*live* binding on `Hyprland.focusedMonitor` — so the shelf follows the focus to another
monitor mid-use. `GlobalStates.dropShelfScreen`, set by whoever opens it, the way
`desktopMenuScreen` already is.

**Out of scope.** Dragging the whole pile out in one gesture — the service already models it
(`copyAll` emits a uri-list) and `DragProxy` would need a list rather than a path, but it is
a feature, not a defect, and it gets its own row. `maxItems: 30` silently dropping the 31st.
`DesktopMenu`'s own hand-assembled `ArrowPopup` motion, which decision 14 leaves to its row.
