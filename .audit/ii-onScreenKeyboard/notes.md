# ii-onScreenKeyboard — notes

## For the cohesion pass, at 60fps

- **The enter and the exit, which did not exist at all.** The card rises out of the
  bottom screen edge on `elementMoveEnter` (500ms default spatial) and drops back on
  `elementMoveExit` (130ms fast effects). Both were measured here rather than eyeballed:
  a probe on `openedProgress` logged 29 frames for the rise, peaking at **1.014** — the
  spatial overshoot DESIGN.md 2.1 asks for — before settling at 1.000. What a still
  frame cannot answer is whether a 320px drop in 130ms reads as *dismissed* or as
  *cut*. `elementMoveExit` was chosen to match `MinimalistOsd`, which landed in the same
  cluster; if it reads as a cut, the alternative is `elementMoveEnter.duration / 2`
  (250ms), which is the "roughly half the enter" of 2.5 and is on the AOSP ladder.

## Measured, not guessed

- **The exit's real defect was an ordering race, not a missing animation.**
  `Loader.active: GlobalStates.oskOpen || root.isClosing` — the shape the rest of this
  cluster uses — does not work here. The binding and the `Connections` that starts the
  exit hang off the same `oskOpenChanged` signal in an undefined order, and the binding
  won *every* time: a `console.log` in the close branch never printed once, and the
  layer unmapped **45ms** after the request. `active` now reads one latch that only the
  component itself clears, and the surface holds for **~180ms** (130ms of exit plus
  teardown). Both numbers are from polling `hyprctl layers` after the IPC client exits.
  `MinimalistOsd` and the cheatsheet still use the `||` form; whether they are lucky or
  structurally different was not established, and is worth one probe each.

- **The per-key framebuffer stays.** `RippleButton`'s background is `layer.enabled: true`
  with an `OpacityMask`, and the US layout instantiates **76** of them — a flat read of
  DESIGN.md 8 ("never an effect inside a delegate that can appear more than ~20 times").
  It is not fixed here and `check-effect-budget.py` does not see it, for the same reason
  it missed the dock: the delegate is its own file. Left alone deliberately —
  `RippleButton` has 261 callers and rule 9 / anti-pattern 1 are explicit that a spec
  applied to a shared base needs a measured before/after, and DESIGN.md 9 prescribes
  `RippleButton` for exactly this. The cost is bounded: the layers are static, so they
  are re-rendered only on a state change, and 76 × 48 × 48 × 4B is ~700KB of VRAM.
  The fix, if it is ever wanted, is in the library — a `layer.enabled` that follows
  `rippleEnabled` — not in this surface.

- **`VerticalButtonGroup` needs `Layout.alignment` from its caller.** It binds its own
  `height`, so inside a `RowLayout` it lands at an offset nobody chose — measured 63px
  above the card's centre before `Qt.AlignVCenter` was set. Every other caller is in a
  container that happens to be the group's own size, which is why this has not been
  seen. Worth a look during the shared-widget follow-ups.

## The open Caps slot (follow-up, same day)

The two `empty` spacers in every home row are deliberate -- all three layouts comment
Caps out with the same note, *"not needed as double-pressing shift does that"*, which is
the 300ms double-release in `OskKey.qml`. The stagger they left behind was not: two 1u
holes are 104px where the `caps` width already in the table is 91px, so every home row
sat **23px** right of the row above when a physical board puts it 7-14px right. Now one
spacer at `shape: "caps"`, and spacer-ness moved off the shape onto `keytype: "spacer"`
-- `shape` is a width token and nothing else, which is what made a sizeable spacer
impossible before. `shape: "empty"` no longer exists.

German had a second hole at the *end* of its home row, where Enter was commented out
because a DE Enter is tall and spans two rows. Both halves are keycode 28 and both
`expand`, so restoring it gives two Enters that fill to the same right edge and read as
the one tall key again -- verified against all three layouts rendered together.

**Not done: the real Caps key.** Keycode 58 through ydotool would toggle the system's
caps lock, but this shell models shift state itself (`Ydotool.shiftMode`), so the OSK
would keep rendering lowercase while the user typed uppercase. That is wiring, not a
data edit. Worth noting that nothing on the surface says double-tap-Shift exists --
`labelCaps` only appears once caps is already locked.

## Tried and rejected

- **`asynchronous: true` on the Loader.** A first probe showed the rise starting at
  progress 0.79, which looked like ~76 widgets' construction eating 400ms of the 500ms
  enter. It was not: that probe was taken against the broken latch. With the latch
  fixed the rise plays from 0.058, so there is nothing for async to buy, and it would
  have put a `Connections` under async incubation for no reason (anti-pattern 5).

- **Hiding the layout button with `visible` alone.** `VerticalButtonGroup.contentHeight`
  sums every child's `baseHeight`, visible or not, so a hidden third button leaves the
  rail a button taller than its content. The button's `baseHeight` collapses to 0 as
  well, which is one expression and keeps the group's arithmetic honest.

## Testing this surface at all

Nothing about the OSK is reachable without driving real input, and two things make that
harder than it looks:

- **`hyprctl dispatch movecursor 660 982` is a Lua syntax error in this config**, and
  the Lua wrapper exposes no `movecursor` at all (`hl.dsp.*` has 8 dispatchers, none of
  them the cursor). `ydotool mousemove -a` does not land on the pixel you ask for
  either. What works is walking there with capped relative `ydotool mousemove` steps
  against `hyprctl cursorpos` — `tools/audit/` has no helper for this yet and probably
  should.
- **The card moves between observations.** The window is bottom-anchored, so the dock's
  exclusive zone shifts it by 62px whenever the dock pins itself. Any coordinate has to
  be measured from `hyprctl layers` and the frame *in the same step* as the click, or it
  lands on the wrong button — that cost three false results here, one of which looked
  exactly like the cycle button not working.

The input-region check AUDIT.md requires for a `mask` change was done twice, at two
different card positions: a held press on Shift (both Shift keys filled `colPrimary` and
every label switched to its shifted glyph) and a click on the layout button
(`English (US)` → `German`, written through to the config).
