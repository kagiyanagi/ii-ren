# ii-sessionScreen — brief

**Purpose.** Pause or end the session: lock, sleep, hibernate, log out, shut down,
reboot, or reboot into firmware setup. Ctrl+Alt+Delete opens it, so it also starts
the task manager.

**Primary action.** The focused tile, which Enter fires. Lock has focus on open,
because it is the one tile where a reflexive Enter cannot lose work.

**Hierarchy.** One card in the middle of the screen, holding eight tiles in two
rows, with each tile's label underneath it. Only one thing on screen is `colPrimary`,
and it is round: the focused tile. The rows now mean something. The top row keeps
your work (Lock, Sleep, Hibernate, Task Manager). The bottom row closes every window
(Logout, Shutdown, Reboot, Reboot to firmware settings). Compared with the old grid,
Logout and Hibernate swapped places and nothing else moved. When a download or the
package manager is detected, the warning goes under the grid as a `NoticeBox` in its
error tone, next to the row it is about. There is no title, instruction paragraph, subtitle pill
or tooltip.

**Reference.** Android's power menu, `GlobalActionsDialogLite`: one card over a dim,
circular icon buttons with the label under each (`global_actions_grid_item_lite.xml`),
and a tap outside dismisses it. There is no title and no help text. The tiles are M3E
Large icon buttons (`LargeIconButtonTokens.kt`): 96 container, 32 icon, the square
container at `CornerExtraLarge` going round when selected
(`SelectedContainerShapeSquare` = `CornerFull`). Tile gap
and row gap are the menu's `global_actions_lite_padding` (24). AOSP caps the menu at 2
columns (`power_menu_lite_max_columns`), which suits a portrait phone. A landscape
desktop gets 4 columns, which puts the same eight tiles in two rows.

**Interaction.**
- `WindowDialog` provides the scrim, the card and both halves of the motion. The scrim
  fades on `elementMoveFast`. The card comes in on `elementMoveFast`/`emphasizedDecel`
  and collapses on half of that with `emphasizedAccel`. The body fades out on
  `elementMoveExit`. That is the shell's dialog recipe (DESIGN.md 9), and polkit
  already runs full-screen on it. The window latches (`rendered`) on the open edge
  and is released once the dialog has collapsed. `Loader.active` reads nothing but
  `rendered`. Until now the surface mapped and unmapped on the same frame as the flag,
  and `no_anim` in `rules.lua` meant Hyprland did not animate it either.
- Transform origin: the dialog's own vertical slide. It is centred on screen and opened
  from a keybind or from the dashboard's button, so there is nothing to grow out of.
- Tile at rest: `colSecondaryContainer` at `rounding.large`. Hover:
  `colSecondaryContainerHover`. Focus: `toggled`, so `colPrimary` and round. The shape
  animates on RippleButton's own `elementMoveSmall`, and colour on `elementMoveFast`.
  Pressed: the ripple and the 0.10 film. A press also takes focus, so while the dialog
  leaves, the highlighted tile is the one you chose. Disabled: 0.4 on the tile and its
  label, both fading on `elementMoveFast`. (Decided while building: no pressed shape.
  M3E gives round icon buttons `CornerLarge` when pressed, but here the pressed tile is
  always the focused one, which rests round, and DESIGN.md 4.3 does not square a
  circle on press.)
- **Hover never moves focus.** The pointer is usually already resting where the card
  opens. If hover moved focus, Enter would fire whatever the pointer happened to be
  over, which is how the old grid showed two "selected" tiles with two different
  names.
- Keyboard: the arrows move around the grid. Left and right stay within the row, and
  every direction skips a disabled tile. Tab follows row order. Enter fires on press,
  and Space works through `Button`. Esc and a click outside the card close it. A click
  inside the card between two tiles does nothing; it used to close the menu.

**Edge states.**
- *An action this machine cannot do:* logind's `Can*` answers `na` or `no`, so the tile
  is disabled and the keyboard skips it. `challenge` stays enabled, because polkit will
  ask. With no answer yet, or a failed query, the tile stays enabled. On this machine
  `CanHibernate` is `na`. The old Hibernate tile closed the menu and did nothing.
- *Warning:* a line under the grid, and the card grows to fit it, since `WindowDialog`
  follows its content while shown. With both warnings, there are two lines.
- *Loading:* both probes answer within milliseconds of opening. Until then every tile
  is enabled and there is no warning.
- *Screen locks while open:* the menu closes. Unchanged.
- *Reopened during the exit:* the dialog reverses, and the window never unmaps.
- *Several monitors:* the menu opens on the focused output and fills it. It used to take
  its height from whichever monitor had focus at the time, not from the one it was on.
- *Long translations:* a label wraps to two lines and elides after that.
  `Neustart zu Firmware-Einstellungen` and `Redémarrer dans les paramètres du firmware`
  are the long ones. Every existing string is kept, so all 14 translations still apply.

**Cost.** One cached shadow from `WindowDialog`, plus each tile's own RippleButton mask.
That makes 8, the same number there were before. No new effects. Opening the menu runs
one more short process (the logind query), next to the two warning probes.

**Delete.** `SessionActionButton.qml` (folded into the one delegate), the eight
copy-pasted tile blocks and their twenty `KeyNavigation` lines, the hand-drawn scrim
and its full-window `MouseArea`, the title, the instruction paragraph, `DescriptionLabel`
(the subtitle it showed, and the two warning pills, which are `NoticeBox`es now), the
tooltip, `focusedScreen`, and `keyboardDown`. Also the
tile's second radius `Behavior`, which ran on the effects spec on top of RippleButton's
spatial one.

**Out of scope.** `WindowDialog`'s own motion. Its enter slides a card that is already
opaque, which is a question for the cohesion pass, across all of its callers.
`waffle-sessionScreen`, its own row, which can read the new capabilities later.
`Session.qml`'s actions: `closeAllWindows` sends SIGTERM to every window before power
off, and nothing asks first. The layer rules: `no_anim` stays, because the shell
animates this surface itself.
