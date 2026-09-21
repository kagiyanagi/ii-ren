# ii-keypressDisplay — brief

**Purpose.** Show the keys being pressed, legibly, inside a screen recording — for a
viewer watching the video later, not for the person at the keyboard.

**Primary action.** None: nothing here is clickable (the window masks an empty region).
The single job is *reading the key that was just pressed off a compressed video frame*,
so contrast and staying on screen beat everything else. Both of those were broken in
ways no screenshot of this machine showed.

**Hierarchy.** A single horizontal row of pill chips, newest at the tail. Shortcut chips
(`colPrimaryContainer`) first to the eye; typed text chips (neutral container) second;
nothing third — there is no title, no icon, no container behind the row.

**Reference.** The Android 16 key-event overlay / M3E assist chip row: full-radius pill,
one line of DemiBold label, elevation 2 for separation from whatever is behind it.

**Interaction.** No states — nothing is hoverable or pressable, so rule 6 does not apply.
Chip enter: opacity on `elementMoveFast` (effects), scale on `elementMoveEnter` (default
spatial, may overshoot). Chip exit: opacity on `elementMoveExit`, scale on
`elementMoveFast`. Reflow of the surviving chips on `elementMoveFast`, and the row's own
scroll on `elementMoveSmall` (fast spatial — it is position, not opacity). Transform
origin `Item.Center`, stated: a chip appears in place, it did not come from anywhere.

**Edge states.**
- *Empty* — `KeypressService.visible` is false and the window does not exist. The whole
  surface appearing and disappearing is deliberately unanimated: it is a recording
  overlay, and a fade on the way out is a fade that lands in the footage.
- *One chip* — row is centred, or edge-anchored per `position`. Unchanged.
- *Overflowing* — the row is wider than the screen at twelve keys, or at scale 2.0, or
  with merged words on a 1366 screen. The view pins to the tail so the **newest** chip is
  the one kept; the oldest scroll off the far end. A ListView's default is the exact
  opposite, and the default is wrong for every recording ever made.

**Cost.** Zero layers, zero blurs. The one effect is `StyledRectangularShadow` per chip,
and it **stays**: DESIGN.md 8 lists a cached `RectangularShadow` as cheap and draws the
line at ~20 repeats, the settings slider caps `maxKeys` at 12, and
`check-effect-budget.py` excludes it by name for that reason. `pack.md`'s effect census
lists every effect including the cheap ones; it is not a verdict.

**Delete.** Nothing. The surface is 176 lines and every one of them is load-bearing.

**Out of scope.** `KeypressService` (the reader, merging, expiry, IPC) and the settings
page that configures it. This row is the drawn surface only.

**Noted, not fixed here.** `Appearance.contentTransparency` reads
`autoContentTransparency` (0.9) without consulting `appearance.transparency.enable`,
unlike `backgroundTransparency` right above it, so every `colSurfaceContainer*` in the
shell resolves at alpha 0.1 out of the box. That is correct for a panel composited over
its own layer and wrong for anything painted on a transparent window; this surface works
around it locally, and whether the fall-through is intended is an `Appearance` question.
