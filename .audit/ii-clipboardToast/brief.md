# ii-clipboardToast — brief

**Purpose.** Confirm a copy landed, show what was copied, and put the two or three
things worth doing with it one click away — then get out of the way.

**Primary action.** Open the clipboard history, from the preview tile. Everything else
is a shortcut for a case that may not apply (a link, a phone on the other end) and must
read as secondary.

**Hierarchy.**
1. The preview tile — largest, lightest, nearest surface, text sized to be readable
   across the room.
2. The action circles — filled `colPrimary`, in a row on the pill behind and below.
3. The pill — a neutral `colLayer0` tray. The ground the circles sit on, never a control.

**Reference.** Android 16 SystemUI `ClipboardOverlayController`: the card that slides
into the bottom-left corner on copy. This surface is a one-for-one port of it, down to
the 6s timeout and the thumbnail-plus-actions split, so it is the only sensible reference.

**Interaction.**
- Enter: scale 0.8 → 1 on `elementMoveEnter` / `emphasizedDecel`; opacity 0 → 1 on
  `elementMoveFast` so the text is legible while the card is still growing. Origin is the
  screen corner it lives in.
- Exit: scale → 0.8, opacity → 0 on `elementMoveExit` / `emphasizedAccel`.
- Reposition — a sidebar opening, a notification landing — on `elementMove`, not
  `elementMoveEnter`. That trip is driven by a toggle and must reverse mid-flight (2.7);
  `elementMoveEnter` runs to end and queues the whole journey on a quick reversal.
- Resize on a second copy: `elementResize`.
- The preview tile is a **`RippleButton`**, not a `MouseArea` plus a colour ternary.
  Hover, pressed and a ripple clipped to its own radius come from the widget (9, 3.2).
- The action circles stay `RippleButton` at 48 / `rounding.full` / `colPrimary`.
- **The dismissal clock stops under the pointer.** Six seconds that expire while the
  pointer is crossing the card take the actions with them, and there is no way back but
  copying again. Hover holds the timer; leaving restarts the full clock.

**Edge states.**
- *No actions* (not a link, no phone): pill and row go, the card is the tile alone.
- *Empty text or an image copy*: never shown — `onEntriesChanged` returns early.
- *Screen locked*: the window unmaps. What is on the clipboard is nobody's business.
- *One action*: the pill shrinks to one circle plus its gaps. No special case.
- *Very long copy*: `previewFontSize` floors at `pixelSize.smallest`, text elides at 4
  lines.

**Delete.**
- The tile's `MouseArea`, its hover/pressed colour ternary, its `Behavior on color`, and
  the `extraVisibleCondition` its tooltip needed because a `Rectangle` has no `hovered`.
- `Appearance.rounding.normal + previewFrame.border` as a radius. A literal added to a
  token survives sharp mode, where the token goes to 0 and the frame keeps a 4px arc.
  Frame takes `rounding.large`, tile `rounding.normal` — the card/content-block pair from
  4.2, and the 6px step reads against the 4px mat.
- The bare `duration:` with no curve on both opacity animations. Linear is not the
  effects curve.

**Out of scope.**
- The `previewFontSize` character-metric heuristic. It already carries a `ponytail:`
  comment naming its ceiling; a pixel-exact measure is a rewrite, not an audit.
- The two `StyledRectangularShadow`s. Two elevations on one card is the reference's own
  composition, and `RectangularShadow` with `cached: true` is on 8's cheap list.
- `RippleButton` rendering no focus state. Shared-widget gap, belongs to `common-widgets`
  — logged in FINDINGS.md.
- Swipe-to-dismiss. The reference has it; nothing else on this shell's overlay layer does,
  and `SwipeDismissible` on a masked layer surface is its own session.
