# ii-screenTranslator — brief

Three files, one surface. `ScreenTranslator` (Scope, IPC `screenTranslator translate`,
Super+Shift+T) opens `ScreenTranslatorPanel` on the focused screen. The panel freezes the
screen, lets it be panned and zoomed, and hosts `ScreenTextOverlay`, which runs the pipeline
(grim → tesseract → `trans`, or the local model) and paints each translated block over its
source text on a blurred, colour-matched box.

**Purpose.** Read what is on screen in your own language, in place.

**Primary action.** Reading. There is no button for it: the translated blocks are the
surface. The close FAB, Esc and pan/zoom are secondary.

**Hierarchy.** The frozen screen with the translated blocks laid over their text. While
the pipeline runs, a scrim over it and one status pill in the centre (indicator + what it is
doing). The close FAB, low and centred, clear of the reserved band.

**Reference.** Google Lens / Circle to Search *Translate*: the frozen frame, each block of
text erased and re-set in the target language on a box matched to the page, nothing else on
screen once it lands. The FAB placement is the region selector's, the shell's other
freeze-the-screen surface, so the two read as one family.

**Interaction.**

- **Enter and exit (2.5, anti-pattern 10).** Today there is no exit: the Scope's `Loader`
  goes inactive on the frame the request clears. The Loader is latched, as in the region
  selector: `open` follows `GlobalStates.screenTranslatorOpen`, and the panel releases the
  Loader itself once its fade has reached 0. A reopen during the fade reverses it on the same
  instance, since its results are still good. The whole window fades in on `elementMoveFast`
  and out on `elementMoveExit`, the spec assigned inside the opacity binding (2.9). The
  window is passive while it leaves: an empty mask and `WlrKeyboardFocus.None`.
- **The window is transparent.** It was `"black"`, which a fade would show at once and which
  zooming out below 1 showed around a shrunken screen.
- **Zoom stays between 1 and 5 and the frame stays on screen.** Below 1 the frozen frame
  shrank into a black window, and a pan could drag it off any edge. At 1 there is nothing to
  pan. The cursor says so: open/closed hand only when zoomed.
- **A wheel step zooms by its delta.** It zoomed 10% per *event*. A touchpad sends a stream
  of small deltas, so one flick went from 1× to 5×. A notch (120) is still exactly 10%.
- **The reveal fades on an effects spec.** The scrim faded on `elementMoveSmall`, a spatial
  spec that overshoots, so opacity clipped (rule 3). It is `elementMoveExit` now: the scrim is
  leaving. The indicator's grow-as-it-fades flourish goes.
- **The status is chrome, not content.** It lived in the zoomed layer, so it grew with the
  zoom. The scrim and pill move to the panel, unzoomed. The pill is a `Toolbar`, the same
  surface as the FAB's neighbours elsewhere, so its colours follow the theme instead of
  `"white"` on `#BB000000`.
- **The FAB rises from below the screen edge** on `elementMove`, bound to the window
  showing, to 8 above Hyprland's reserved bottom band. Today it is pushed from
  `Component.onCompleted`, which runs while grim still has the window unmapped, and it
  lands 8 above the screen edge, on the frozen dock.
- **Own namespace.** The panel claimed `quickshell:regionSelector`, so every layer rule and
  tool that looks for the region selector found the translator too. It is
  `quickshell:screenTranslator`, with the same `no_anim` rule the region selector has.

**Edge states.**

- *Preparing* (grim): nothing mapped. A dismiss here releases at once.
- *Working*: scrim + pill, "Reading screen" then "Translating". OCR can take ~10s on a
  text-dense 1080p screen (measured: 144 paragraphs), so this is the state most seen.
- *Error* (no tesseract, no text found, offline, local model deps): the pill shows the
  error icon and the message. The scrim stays. The FAB closes.
- *Nothing to translate*: every block is already in the target language. Today that ends on
  the bare frozen screen with no word, which reads as broken. The pill says so and stays.
- *One block*: one box.
- *Colour detection fails* (no venv, bad crop): boxes fall back to
  `colSecondaryContainer` / `colOnSecondaryContainer`. It is not an error.

**Cost.** The colour of each box came from its own process: a `magick` decode of the
whole screenshot and a Python start that imports cv2, per box, all at once. Measured here:
217ms for one box, 1.7s of all 8 cores for 30, and the boxes changed colour as they landed,
after the reveal. It is one process for every box now, run beside the translation, and the
reveal waits for both, so no box changes colour on screen. Delegates are built only for
blocks that are real translations. Today every OCR paragraph gets two delegates, and each
text delegate binary-searches its font size whether it is visible or not.

The box is opaque in the colour detected under it, and that is what erases the source. It
was 60% of that colour over a masked `MultiEffect` blur of a second copy of the screenshot.
agy's vision pass on the first after-shot found the blurred glyphs showing through wherever
a translation ran shorter than its source (the navy box's trailing した。), and they did. So
the blur, its mask layer and the second 6MB decode go, and with them every offscreen pass
the surface had. *Amended after the first build.*

**Delete.** `overlayColor` / `textColor` literals, the status column and the error column in
the zoomed layer, the `Row` round the lone FAB, the colour `Behavior`s (a box's colour no
longer changes after it is built), the per-delegate `visible:` filter, the `translation`
map and its keys, and the blur: `MaskMultiEffect`, the mask item's layer, the hidden
`StyledImage` and the second `Repeater` that drew the mask.

**Out of scope.** OCR speed (`--psm 11`, `OMP_THREAD_LIMIT=1` are `TextRecognizer`'s).
`trans` detecting one source language for a whole mixed batch, so a French line next to
Japanese can come back unchanged. That comes from the single request, which is there to
avoid rate limits. A language pill and "show original" (features, not audit). Copying a
translated block. Animated zoom. Multi-monitor (it opens on the focused screen, as before).
