# ii-fastPair — brief

**Purpose.** A pair of earbuds just came out of their case. Connect them in one click
without opening anything.

**Primary action.** **Connect.** Today it shares a row with an equal-width Close, and the
Close is the first button in the row, so the eye lands on the wrong one.

**Hierarchy.**

1. The device: its icon in the shape, name under it, one line of status under that.
   Centred, because this is a hero card and that is the Android sheet's posture.
2. **Connect** — the one filled control, full width across the bottom.
3. The options chevron, an icon button beside Connect. Snooze, "never show" and mute live behind it
   and stay behind it.
4. Close — an icon button in the card's top-right corner, where Android puts the X.
   Not a third peer of Connect.

**Reference.** Android's Fast Pair half-sheet (Nearby `HalfSheetActivity`): device image,
name, a single filled Connect, an X in the corner, and a progress bar under the image
while it pairs. Posture from the shell's own sheet recipe (DESIGN 9): slides in from its
screen edge.

**Interaction.**

- Enter: slide from the configured edge on `elementMoveEnter`. Exit: slide back out on
  `elementMoveExit` — half the duration, accelerating. Today both directions run on the
  enter spec (DESIGN 2.5). The spec is picked *inside* the binding that writes `x`, the
  `BarComponent` shape, because a spec read from its own binding is a frame late.
- Vertical moves (a notification stack appearing above it) on `elementMove`.
- The options reveal stays on `Revealer`. The chevron's rotation is a spatial property and
  moves on `elementMoveSmall`, not `elementMoveFast`.
- Origin: the screen edge it came from. No scale, so no pivot arithmetic.
- Buttons are `DialogButton`/`RippleButton`, which carry all four states. Icon buttons are
  sized square, `rounding.full`, `padding: 0`, hit area 40 (DESIGN 9).
- Disabled Connect is the button at `opacity: 0.4` (DESIGN 6), not a filled primary with
  outline-coloured text.
- Escape is not wired and stays that way: the popup is `Overlay` and must not take the
  keyboard from whatever the user was doing.

**Edge states.**

- *Idle* — "Nearby and ready to pair", Connect enabled.
- *Busy* — the indeterminate bar fades in under the icon on `elementMoveFast`, Connect
  goes disabled, status walks "Pairing…" → "Connecting…" → "Connected". The bar's row is
  always reserved so the card does not jump.
- *Failed* — status in `colError`, Connect back on for the retry.
- *No agent* — status names the binary, Connect disabled: it cannot succeed.
- *No candidate* — reachable from `ipc call fastPair preview`. Generic bluetooth icon
  and "Bluetooth device"; every button works.
- *Locked* — hidden, already.

**Cost.** The one `StyledRectangularShadow`, kept. The indeterminate bar runs its two-segment
sweep only while `busy`, on a 4px strip. Nothing repeats with an effect in it.

**Delete.**

- Close as a full-width text button in the action row.
- `padding: 24` on the card (recipe says 12–16), `iconSize: 72 / padding: 32` on the hero
  (icons are 40–48 for a tile), `spacing: 6`, `bottomMargin: 10/12`, `topMargin: 2/6`, the
  chip `padding: 10`, the chevron's `implicitWidth: 36 / padding: 6`. The card's width moves
  into `Appearance.sizes`.

**Out of scope.** `services/FastPair.qml` and the advert parser. The corner setting and the
stacking handshake with notifications, screenshot preview and clipboard toast
(`GlobalStates.fastPairPopupHeight`) — it works and three consumers read it.
