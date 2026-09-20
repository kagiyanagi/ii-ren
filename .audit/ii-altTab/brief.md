# ii-altTab — brief

**Purpose.** Show which window Alt+Tab is about to land on, for as long as Alt is held,
and name it. Nothing else.

**Primary action.** Release Alt on the right window. The card is a readout for a decision
being made on the keyboard; the pointer is a secondary way to reach the same thing.

**Hierarchy.**
1. The selected tile — the `colSecondaryContainer` highlight that slides under the icons.
   It is the only filled surface in the card and the only thing that moves.
2. The icon grid. All tiles equal; the highlight is what distinguishes one.
3. The title, under the grid, `colOnLayer0` at body size.

**Reference.** GNOME Shell's `altTab.js` switcher, not an Android surface — Android has
no keyboard window switcher, and inventing an AOSP lineage for one would be a fiction.
What is borrowed from it is the one thing that makes a switcher usable and this one does
not do: **`POPUP_DELAY_TIMEOUT` — the popup does not appear until the modifier has been
held 150ms.** Everything the card is made of still comes from `DESIGN.md`: it is a
centred overlay card, so its motion is the dialog recipe (9) that `WindowDialog` already
ships.

**Interaction.**
- **Held, not tapped.** `open` (the switch is in progress) and `shown` (the card is on
  screen) separate. A tap-and-release Alt+Tab never shows a card at all.
- Enter: scale 0.92 → 1 and opacity 0 → 1 over `elementMoveFast.duration` on
  `emphasizedDecel`. Exit: the same properties over half that, on `emphasizedAccel` (2.5,
  and the pairing `WindowDialog` writes out). Spec assigned from inside the binding that
  drives the animation, per 2.9's Behavior trap.
- Transform origin `Item.Center`, stated: the card is centred on the screen and comes out
  of nothing (2.6).
- The highlight slides on `elementMove` — a position, so a spatial spec, which the one
  shared duration it has today is not.
- **The highlight does not slide while the card is hidden.** Selecting the 8th window,
  confirming, and re-opening otherwise animates the highlight back across the card as it
  fades in, from a value that was never on screen (2.7, reset on hide).
- Four states on a tile: hover and focus are both *the selection itself* — moving the
  pointer over a tile moves the highlight to it, which is louder than a 0.08 film and is
  also exactly what the keyboard does. Pressed is a `StateLayer` at `Press` over the tile,
  in `colOnSecondaryContainer`. Disabled does not exist here.
- `Qt.PointingHandCursor` on the tiles (3.4).
- **Escape cancels**, leaving focus where it was (3.7). The window takes no keyboard
  focus, so this is a `GlobalShortcut` plus an `ALT + Escape` bind, not a `Keys` handler.

**Edge states.**
- *No windows*: `step()` returns before opening. Unchanged.
- *One window*: one tile, and the title cell floors at three tiles wide so the card does
  not collapse to 80px of chrome around a name.
- *More windows than fit*: **today they paint outside the card and off the screen.** The
  row becomes a `Grid` whose column count is whatever fits in 90% of the screen, and the
  rows are balanced (`ceil(n / rows)`) so the last one is not a single orphan tile.
- *Missing icon*: `image-missing`, unchanged.
- *Long title*: elides, unchanged.
- *Target on another monitor*: the monitor the switcher opened on is latched at open, so
  the card finishes its exit instead of being unmapped the instant focus lands elsewhere.

**Cost.** One `StyledRectangularShadow`, kept — the card is elevation 5 and it is the only
effect on the surface. The press film is a `Rectangle`, not a layer, so per-tile is fine
(8 is about `layer.enabled` and shaders). Nothing new.

**Delete.**
- `AltTabAnim` and its `110 * animMultiplier`. One hand-picked duration on the effects
  curve was driving scale, opacity and a position, in both directions. The delay is what
  makes real tokens affordable, so the invented number has no job left.
- `padding: 18`, `iconSize: 58`, the `260` title floor — off the grid or out of 5.4's
  icon range, and the floor is now three tiles.
- `visible: root.open` on the panel. It unmaps the window the instant the switch is
  confirmed, so the exit animation has never once rendered.
- The click path's silent wrong-window bug: `onPositionChanged` sets the selection but
  `onPressed` does not, so clicking a tile the pointer was already resting on confirms
  whatever the keyboard had selected instead.

**Out of scope.**
- The `no_warps` handover and its 600ms restore timer. Compositor plumbing, correct, and
  the one literal in it is a Hyprland animation length rather than a motion token.
- Window thumbnails instead of icons. That is a different surface, needs screencopy, and
  the brief for it is not this one.
- `Appearance.animMultiplier`. `AnimSpec` does not apply it anywhere in the shell (2.9),
  and 200ms is not long enough to be worth a disable path.
