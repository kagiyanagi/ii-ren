# ii-immersiveMedia — brief

**Purpose.** Put the thing that is playing on the whole screen, and let you read along
with it.

**Primary action.** Play/pause. The 64dp accented transport button is the only filled
control on the surface; everything else is glass over the album art and must look it.

**Hierarchy.** 1) the album art, 2) the track title, 3) the current lyric line,
4) the transport row, 5) chrome — the player chip, the lyrics toggle, close.

**Reference.** Android 16's full-screen media player: art as the hero, controls anchored
under it, lyrics as a second surface rather than a mode. The two-pane split is the desktop
concession — a 16:9 screen has room for both at once, where a phone has to swap them.

**Interaction.** Enter and exit are the one thing this surface gets wrong today and the
main reason for the row.

- The surface grows from its own centre (2.6) — a fullscreen overlay has no control to
  grow out of.
- Enter: `contentScale` 0.94 → 1 on `elementMoveEnter` (spatial, overshoots),
  `opacity` 0 → 1 on `elementMoveFast` (effects, may not overshoot). Two properties,
  two specs, two durations — 2.1.
- Exit: both on `elementMoveExit`, the token that exists for exactly this. Today the
  exit hand-computes `enterDuration / 2` and picks `emphasizedAccel`, which is a
  number and a curve invented next to the token that names them (rule 2).
- Everything else keeps its four states through `RippleButton`; the glass buttons hold
  their rest alpha across hover/pressed so what reads is the M3 state layer and not a
  jump to a solid fill. That is already right — leave it.

**Edge states.**
- *No player.* Chip reads "No player", title "Nothing playing", art falls back to a
  `music_note` glyph, every transport button disabled at 0.4. Already correct.
- *No lyrics.* `PagePlaceholder`, which distinguishes "nothing found for this track"
  from "lyrics are turned off". Already correct.
- *Plain lyrics, no timings.* A `StyledFlickable` of wrapped text. Today it wraps at the
  full pane width, which on a wide screen is a wall — bound it to a measure.
- *One player.* The chip stays enabled and reads as a label rather than a switcher;
  disabling it at 0.4 would hide the player's name. Already correct, and commented.

**Cost.** One effect on the surface: the `layer.enabled` + `StyledBlurEffect` on the
background art. Keep it, add nothing. `LyricLine`'s per-line `OpacityMask` is 6 passes
inside `LyricScroller`'s `Repeater` but under the ~20 ceiling in rule 8, and it belongs to
`cw-media` — note it, do not touch it from here.

**Delete.**
- The static "Media Player" label in the toolbar. The surface is a fullscreen media
  player; the label says nothing and leaves the chip stranded mid-row.
- `enterDuration` / `exitDuration` on the content, once the tokens replace them.

**Layout — the one restructure.** The now-playing card is sized by a guess
(`min(540, width * 0.36)`) and the album art is square, so on a 1920×1080 screen the art
caps at 508 against 684 of available height and ~180px of the card is void, while the
lyrics pane takes 68% of the screen to centre a 350px-wide line in it. The card should be
**as wide as the art can be tall** — the art is square, so any other width is a void on
one axis or the other. The pane publishes its own fixed vertical budget and the content
sizes the card from the row height, capped at a fraction of the screen so a very tall
screen cannot eat the lyrics. Height never depends on width here (every label elides
rather than wraps), so the binding resolves in one pass — verify that in the log rather
than assuming it.

**Out of scope.** The art-download `Process`, which is the same eight lines repeated in
thirteen files across the shell and wants one shared helper, not a fourteenth copy.
`LyricScroller` / `LyricLine`, owned by `cw-media`. The `media.immersive` config keys and
their settings page.
