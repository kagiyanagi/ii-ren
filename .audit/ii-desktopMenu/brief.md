# ii-desktopMenu — brief

**Purpose.** Right-click on the desktop: change the wallpaper, or act on the
desktop widget under the cursor. Two modes in one card, chosen by
`GlobalStates.desktopMenuWidgetId`.

**Primary action.** Pick a wallpaper. Everything below the strip is a secondary
route to the same thing (browse, shuffle, file picker) plus two unrelated
escapes (drop shelf, settings). In widget mode the primary action is *Remove*,
and it is last because it is destructive.

**Hierarchy.** The wallpaper strip leads — it is the only thing in the card with
colour in it. Then the five rows, each an equal-weight 52dp surface; nothing in
the stack outranks its neighbours and nothing should try to. In widget mode the
strip is gone and the rows are the whole card.

**Reference.** Launcher3's `ArrowPopup` — `bg_popup_item` 216×52dp rows stacked
with `popup_margin` 2dp, the big radius only at the ends of the stack, and
`setPivotForOpenCloseAnimation()` growing the card out of the corner nearest the
touch point. The wallpaper strip is the Android wallpaper picker's row: tiles
with a gap, the active one wider than the rest.

**Interaction.** Open on `arrowPopupScale` → `arrowPopupOvershoot` over
`arrowPopupScaleDuration` on `emphasizedDecel`, settling on `arrowPopupSettle`
over the same duration, with the card and its content fading in underneath over
`arrowPopupFadeDuration`. Close on `emphasizedAccel` over
`arrowPopupCloseDuration` with the fade held back `arrowPopupFadeHold` — the
same composite the bar popups, the systray menu and the combo boxes already
assemble, so it must come from the same tokens rather than from numbers typed
beside them. Transform origin follows the cursor, not the corner the edge clamp
left the card on. Tile width animates on `elementResize` (spatial, may
overshoot); the scrim and the check mark fade on `elementMoveFast` (effects,
must not).

The card takes the keyboard exclusively, so it answers to it: Up/Down walk the
row chain via `nextItemInFocusChain`, Return/Enter/Space fire the row,
everything else dismisses. Same pattern as `SysTrayMenuEntry`, which needs
`focusPolicy: Qt.StrongFocus` because `RippleButton` fires from its own
`MouseArea`. Without this, `ipc call desktopMenu toggle` — the row's own
documented open path, which centres the menu because there is no cursor — opens
a menu that cannot be used at all without reaching for the mouse.

**Edge states.**
- *Empty* — no wallpapers at all: strip hidden, five rows, card shrinks to fit.
- *One item* — the only wallpaper is the one already applied: **strip hidden**.
  It is 132dp of card that can only re-select what is already selected, and on
  this machine it is the live state, because `Wallpapers.directory` defaults to
  `~/Pictures/Wallpapers` and the user's wallpapers are elsewhere. This is the
  visible defect in `shot-before.png`.
- *Loading* — thumbnails arrive late; `ThumbnailImage` fades each in over
  `elementMoveFast` against the tile's `colSurfaceContainerHigh` placeholder.
- *Widget mode* — strip and all five desktop rows hidden; the depth row hides
  again unless the wallpaper has a subject and desktop depth is on, so the card
  is four or five rows.

**Cost.** Keeps: the card shadow, and the one `OpacityMask` that rounds the
strip viewport's cut ends. Keeps, under protest: the per-tile `OpacityMask` that
rounds each thumbnail. It is in `check-effect-budget.py`'s `KNOWN` set as
shrink-only, and every way out costs more than it saves — `RoundCorner` is four
`Shape` layers per tile, and masking the whole strip once means re-deriving each
tile's position from `contentX` by hand. Recorded in `notes.md` rather than
traded for something worse.

**Delete.**
- `WidgetActions.qml` — 83 lines, reached by nothing. The rows it holds were
  copied into `DesktopMenu.qml` and the file was never removed.
- Ten copies of the same twelve styling properties. One inline `MenuRow`
  component holds the Launcher3 row metrics, the state-layer mix and the
  keyboard, and each row keeps only what makes it that row.
- The hand-typed open/close timings, in favour of the `arrowPopup*` tokens that
  `Appearance.qml` already names this file as a caller of.

**Out of scope.** Moving `DockMenuButton` into `modules/common/widgets/` — the
`ponytail:` comment at the top of the file asks for it and there are now four
callers, but three of them are `modules/ii/dock`, whose own queue row is still
open. It belongs to `ii-dock`, not here. Also out: `Wallpapers.directory`
defaulting to a folder that does not exist, which is a services concern.
