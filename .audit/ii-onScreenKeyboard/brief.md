# ii-onScreenKeyboard — brief

**Purpose.** Type into the focused window with the pointer when there is no usable
physical keyboard — a VM, a handheld, a lap-held tablet mode, a broken key.

**Primary action.** Press a key. Every pixel that is not a key is chrome and must look
like chrome: the pin, the hide and the layout cycle are three small round buttons on a
rail, and nothing else may compete with the grid.

**Hierarchy.**
1. The key grid — the whole width of the card, the only thing with a filled container.
2. The oversized keys that end a gesture: Space, Enter, Backspace, Shift.
3. The control rail — round, 40dp, left of the grid, read as *not a key* by shape alone.

**Reference.** Gboard on Android 16. A bottom-edge sheet that rises out of the screen
edge, keys as flat tonal surfaces on one card, word labels smaller than character
labels, no chrome inside the grid. Chosen because it is the only Android surface that is
this — a dense tap grid the user looks *through* rather than at.

**Interaction.**
- Enter: the card rises out of the bottom edge on `elementMoveEnter` (default spatial,
  may overshoot). Travel is an **anchor margin**, never a transform — the window masks
  this item and `mask: Region` bakes a transform into the input region and never refreshes
  it (`tools/check-mask-regions.py`).
- Exit: back down on `elementMoveExit` (fast effects). The surface must outlive the
  request; `Loader.active` bound straight to `GlobalStates.oskOpen` destroys it on the
  frame the flag clears and there is nothing left to animate.
- Transform origin: the bottom screen edge, which is what the card is anchored to (2.6).
  No opacity ramp — the screen edge does the masking, as the compositor clips the layer
  surface at its own bottom.
- Keys: `RippleButton`'s four states, ripple from the press point (3.2 — a key is the
  textbook case for a ripple). Shift and the latching modifiers use the `toggled` fill.
- Rail: `GroupButton` in a `VerticalButtonGroup`, `rounding.full`, so a round button
  next to square keys is unmistakably chrome.

**Edge states.**
- *One layout.* The cycle button is not rendered — one layout is not a choice.
- *Unknown layout name.* `Config.options.osk.layout` falls back to `defaultLayout`; the
  shipped default `"qwerty_full"` matches no layout in `layouts.js` and is corrected to
  the real name, so the knob stops being dead.
- *Spacer keys.* `shape: "empty"` is layout padding (the US home row drops Caps because
  double-tapping Shift locks it). It holds its cell, paints nothing, takes no input.
- *Locked screen.* The window hides; it must not be typeable through a lock.
- *Long label.* A word label steps down to `pixelSize.small`. At `large` the 4-character
  "Menu" elided to "Me…" on a key wide enough to hold it.

**Cost.** One `StyledRectangularShadow` on the card, unchanged — the pack's only entry.
Nothing new. `RippleButton`'s `OpacityMask` framebuffer repeats once per key (~76 on the
US layout) and stays: it is the library's, shared with 261 callers, and DESIGN.md 9
prescribes `RippleButton` for exactly this. Measured and recorded in `notes.md` rather
than fixed here (anti-pattern 1).

**Delete.**
- The 1px `colOutlineVariant` bar between the rail and the grid (law 11 / 5.5).
- The `Keys.onPressed` Escape handler. The window deliberately never takes keyboard
  focus — taking it would break the one thing the surface does — so the handler has
  never been reachable.
- `visible: oskLoader.active && …`, which is tautological inside the loader's own
  component and is half of why there is no exit.

**Out of scope.** `layouts.js` key data (three layouts, generated against
`input-event-codes.h`), the `Ydotool` service, the shift/caps state machine, and
`RippleButton` itself.
