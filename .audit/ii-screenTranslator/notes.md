# ii-screenTranslator — notes

**How to drive it.** `qs -c ii ipc call screenTranslator translate`, or Super+Shift+T. It
maps ~210–300ms after the call, once grim has written the screenshot. **There is no close
IPC**: `translate` only opens, so close it with Esc (`ydotool key 1:1 1:0`; `OnDemand` focus
lands on map) or the FAB. **The live config is `language.translator.mode: "local_model"`**,
and mokuro/argostranslate are not installed here, so the shipped path on this machine ends
in the error pill after a second or two. The tesseract + `trans` path needs the mode set to
`"lightweight"`: flip it in `~/.config/illogical-impulse/config.json`, drive, and flip it
back (this row did, and diffed the file against a backup afterwards). tesseract here has
`jpn` and `eng`, and `Translation.languageCode` is `en_US`, so Japanese text is what makes
boxes.

**Foreign text on screen.** A `qs -p` probe, a layer-shell `PanelWindow` on `WlrLayer.Top`
with four lines in it (three Japanese, one English), 880×520 at (520, 180). A layer does not
tile, so it moves no window, and grim and the screencopy both see it. Kill its pid after.
Kept out of `~/.config/quickshell/ii`, so writing it does not reload the shell.

**Shots are redacted.** Everything outside the probe card and the bottom strip is
pixelated, because the frozen screen behind it was a personal browser session.
`shot-before.png` is the old code's error state (the only one reachable on the shipped
config), `shot-after-error.png` the new error state, `shot-after.png` the new finished
state.

## What was wrong

1. **No exit.** The Scope's Loader went inactive on the frame the request cleared. Now it
   is latched and the panel releases it when its fade reaches 0, in the region selector's
   shape, except that a reopen during the fade reverses it on the same panel rather than
   building a new one. The region selector needs a fresh instance for `retrigger`; this
   does not, and its screenshot and translations are still good. Measured over a 60fps
   recording: in 9–12 frames (`elementMoveFast`, 200ms), out in 8 frames ≈133ms
   (`elementMoveExit`, 130). Esc to unmap is 200–250ms, polled through `hyprctl` and
   ydotool. It was 0 before. The window is passive during the fade.
2. **The window was `"black"`**, which a fade would show at once, and zoom went down to
   0.1, where the black showed round a shrunken frame. Zoom is 1–5 now, and `place()`
   keeps the frame on screen. A wheel event zoomed 10% whatever its delta, so a touchpad
   flick went 1× → 5×. It zooms by `angleDelta / 120` now. A horizontal scroll zoomed *out*
   (`angleDelta.y > 0 ? 1.1 : 0.9` is 0.9 at 0); it does nothing now. The cursor is a hand
   only when there is something to pan.
3. **The scrim faded on `elementMoveSmall`**, a spatial spec, so its opacity overshot and
   clipped. It is `elementMoveExit`. The status (indicator + label, error icon + message)
   lived in the zoomed layer in `"white"` on `#BB000000` and grew with the zoom. It is a
   `Toolbar` pill centred in the unzoomed chrome now.
4. **Nothing to translate ended on a bare frozen screen**, which reads as broken. The pill
   now says "Nothing to translate" and the scrim stays.
5. **One colour process per box.** Each box ran `magick` on the whole 6MB screenshot and
   started a Python that imports cv2. Measured: 217ms for one box, 1.7s of all 8 cores for
   30. A text-dense screen gives tesseract 87–144 paragraphs. The boxes were drawn first
   and changed colour as their answers landed. `text_color.py` takes the image and every
   box now (378ms for 33) and runs beside `trans`, and nothing is drawn until both are in.
   On the one crop compared, the output is identical to the old per-crop run.
6. **Every OCR paragraph got two delegates**, visible or not, and each text delegate ran
   its font-size binary search regardless. Delegates are built from `boxes` now, which are
   only the real translations.
7. **The FAB was pushed from `Component.onCompleted`**, while grim still had the window
   unmapped, to 8 above the screen edge, on the frozen dock. It is bound to `visible` and
   sits 8 above the reserved band. Measured: FAB bottom row 1015, band top 1023. It rises
   with `elementMove`'s small overshoot (quarter-scale top 50 → 35 → settles 36).
8. **Namespace.** The panel was `quickshell:regionSelector`. It is
   `quickshell:screenTranslator`, and the region selector's `no_anim` rule is now an
   alternation over both. `~/.config/hypr/hyprland/rules.lua` was identical to `dots/`
   before this row, so it was copied over to apply the rule live.

`tools/check-screen-translator.py`: five checks, each failing on the pre-row tree, and 24
mutations of the new one, all caught (a scratch copy of the five files, so the live shell
never reloads).

## The blur went after the first build

The first build kept the blur: 60% of the detected colour over a masked `MultiEffect` blur
of a second copy of the screenshot. agy's vision pass (`gemini-3.1-pro-high`, `--mode plan`,
absolute paths) found the blurred glyphs showing wherever a translation was shorter than its
source, e.g. the navy box's trailing した。. Checked against the pixels, it was right. The box
is opaque now, which erases the source outright. It also leaves the blur, its mask layer and
the second decode with nothing to do, so the surface has no offscreen pass at all.
`shot-after.png` is the opaque build. The brief's **Cost** says so.

agy's other three findings. The FAB "overlaps the dock": no, it is 8 above the band. The
dock's own pill rises ~7px above its reserved band, the same thing the region selector
measured. "In the error state the FAB closes": it read the brief's "the FAB closes" as a
state rather than a role. "The red box is a tiny square and the text overflows it": the box
is tesseract's, tight to the glyph bodies. That is real but belongs to `TextRecognizer` (in
`FINDINGS.md`).

## Why the wait is so long

On a dense 1080p screen: tesseract 7.5–10s (`--psm 11`, `OMP_THREAD_LIMIT=1`), then `trans`
**17s for 78 lines** in its one multi-line request. So the finished state lands ~25s after
the keybind, and 16s was not enough in the first live run. None of that is this row's (see
`FINDINGS.md`), but it is why the working state is what the user sees most, and why the pill
has to read.

## For the cohesion pass (60fps)

- **The fade in and out**, measured above. As in the region selector, the frozen frame
  cross-fades over a nearly identical live screen, so what is seen is the scrim arriving.
- **The reveal**: the scrim and pill leaving on `elementMoveExit` when the boxes land,
  after up to ~25s of waiting. Not recorded: it needs the lightweight mode and a long
  recording. Watch whether the boxes appearing under a 130ms fade reads as one event.
- **The FAB's rise**, `elementMove`, unchanged spec but now bound, and ending above the
  band.

## Deliberately not done

- **A close or toggle IPC.** `translate` only opens, and a second Super+Shift+T does
  nothing. That made driving it awkward, but it is a feature, not a defect.
- **Animated zoom.** Wheel notches still step 10%. A touchpad is smooth now that the step
  is proportional.
- **Multi-monitor.** It opens on the focused screen, as before. Unmeasured, one screen here.
- **`local_model_translator.py`** is ja→en only and runs on the system Python, not the
  venv. Out of scope. It is also the shipped mode on this machine, with its deps missing.
