# CLAUDE.md — ii-ren

Architecture, commands, config schema and QML conventions: @AGENTS.md

## Design law — applies to every change, unasked

This shell imitates Android 16 / Material 3 Expressive. That is not a feature
request that was fulfilled once; it is the standing spec for everything in it.

**Before writing or changing any QML that draws, moves, or responds to input,
read `.github/DESIGN.md`.** It has the motion tokens, interaction specs, shape
and spacing scales, effect budget and per-component recipes, with every number
traced to its AOSP source. Do not ask whether Android-style motion is wanted —
it is the default. New widgets get it on the first pass.

The condensed version, so nothing is missed even without opening that file:

1. **Reuse first.** ~140 widgets live in `modules/common/widgets/`. A button is
   `RippleButton`, a list is `StyledListView`, a popup follows `DockFolderPopup`.
2. **Never invent a number.** Durations and curves come from
   `Appearance.animation.*` / `Appearance.animationCurves.*`, radii from
   `Appearance.rounding.*`, colours from `Appearance.colors.*`, shared sizes
   from `Appearance.sizes.*`. No literal `duration:`, no hex, no literal radius.
3. **Spatial vs effects.** Position/size/shape animate on a spatial spec and may
   overshoot. Opacity/colour animate on an effects spec and must never overshoot.
4. **Enter and exit are asymmetric.** Enter decelerating on default spatial,
   exit accelerating on fast effects at about half the duration. Both required.
5. **Transform origin is deliberate.** A surface grows out of whatever opened it.
6. **Four states, always.** Hover 0.08, focus 0.10, pressed 0.10, dragged 0.16 —
   via `colLayerNHover`/`colLayerNActive` or `StateOverlay`. Disabled is
   `opacity: 0.4`.
7. **Spacing on the 4dp grid**; child radius smaller than parent radius.
8. **Effects are a budget** — integrated graphics is the target. One
   layer/effect per widget, never inside a repeated delegate.
9. **Do not apply a spec globally to a shared base widget** without checking
   every caller. That is how a pressed-shape default squared 58 pill buttons.
10. **Measure motion at 60fps.** Never eyeball a timing change.

Before calling a UI change done, run `/design-check`. It runs
`tools/check-design.py` for the mechanically checkable rules, then reads the diff
for the ones a script cannot see — transform origin, spatial-vs-effects, enter/exit
pairing, layer nesting, effects in delegates, missed reuse.
`tools/check-m3-tokens.py` asserts the tokens still match AOSP; run it after
touching motion tokens or state layer values.
