# ii-sidebarDashboard-quickToggles — notes

**Opening it.** `qs -c ii ipc call sidebarRight open`. It is the top card. The pencil in
the header row toggles edit mode. A wheel turn over the grid turns the page.

**Driving it with ydotool.** Absolute moves (`mousemove -a`, half coordinates) sometimes
close the sidebar before the click lands, and the click then goes to whatever is behind
it. It happened twice here, and once it landed in the browser. Always check
`hyprctl layers` / a screenshot *after* the move and before the click. Also check
`hyprctl cursorpos` before driving at all: the owner may be using the desktop.

**Measured live.**
- Grid centring: the card spans x 20–445 in the sidebar shot. Tiles were 26–433 (6px
  left, 12px right) and are 26–439 now.
- ThreeWaySlider: after one tap on the power-profile knob, a 35px vertical drag on the
  panel background (away from the dots) moved the whole grid about 10px and clipped the
  dots. After the fix, the same sequence moves nothing.
- Slider tiles do *not* turn the page when dragged. That was checked on the mic slider,
  because the comment on the right-click `MouseArea` claimed it was what prevented it.
  It is not; the comment now says what the area does.
- Every tile size nobody has placed (2x2 and 1x2 Bluetooth/Wi-Fi, 2x1 Bluetooth) was
  rendered in a throwaway `qs -p` window of `FloatingWindow` + `Flow`. The tiles take a
  fake `chooser` `QtObject` carrying `panel { editMode, baseCellWidth, baseCellHeight,
  spacing, columns, editController: null }`. The probe runs with default colours, not the
  wallpaper theme. It was not committed.
- The new page-dot target was not clicked live (the owner was on the desktop).
  `check-quick-toggles.py` runs its real click handler over every pixel of the row.

**System state touched and put back.** A mis-landed click set the laptop speakers to 0.63;
restored to 0.86. The mic was dragged to 0.05 and restored to 1.00. The power profile
went from `power-saver` to `balanced` at some point in the session. The knob taps here
all resolved to power-saver, so that change was probably not this session's, and it was
left alone.

**`tools/p3-quick-toggles/port-toggles.sh` is stale — do not run it.** The tree was
vendored from ii-p3drovfx on 2026-08-28. Since then six local feature commits added
`keyboardBacklight`, `comfortView`, `readingMode`, `hotspot`, `keypressDisplay` and
`location`, and this row rewrote the Bluetooth tile. The script's `SUPPORTED` filter
knows none of those types, and it `cp`s over every file, so re-running it deletes six
features and reverts this row. Unlike `ii-background-widgets`, this tree is ours now.
Either retire the script or rebuild it around a diff.

**Found and left alone.**
- `dots/.config/illogical-impulse/config.json` still ships the pre-grid format:
  `sidebar.quickToggles.android: { columns: 6, toggles: [...] }`, with no `pages`. A fresh
  install gets Config.qml's default pages at *six* columns. `iiren save` from a live
  config fixes it; it was not hand-edited (AGENTS.md).
- The media tile's text is `"white"` over album art darkened by 40% `colLayer0`. In light
  mode that overlay is light, so the contrast is not guaranteed. The tile is not placed
  in the live config. Fix it with the art-derived colours the other media surfaces use.
- The earbud art is four `ColorOverlay` layers (two colours per bud), drawn only while
  a device is connected, and at most one Bluetooth tile exists. The count is unchanged.
- The right resize handle hangs half outside its tile, so on the right column the panel
  clips half of it. It is still grabbable.
- `PowerProfilesToggle`'s status strings ("Power Saver", "Balanced", …) are not
  translated.

**For the cohesion pass (motion), at 60fps.**
- Edit-mode reflow and resize: tiles now move on `elementMoveSmall` (350ms, overshoots),
  where they used `elementMoveFast` (200ms, none). The reflow runs on every pointer move
  during a drag. Watch for jitter while dragging a tile across a row.
- The three-way knob slide, same change.
- The page turn: `emphasizedDecel` at 350ms, where it was `OutQuint` at 350ms.
- Page-height changes and leaving edit mode are now one animation (the panel's
  `implicitHeight`), not two chasing each other. The dots now jump to their new place
  and the card follows. Check that this reads as a reveal and not a pop.
