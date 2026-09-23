# ii-regionSelector — notes

**How to drive it.** `qs -c ii ipc call region screenshot` (also `search`, `ocr`, `qrScan`,
`record`). It maps ~50–100ms after the call, once grim has finished. Esc works without a
click (`OnDemand` focus lands on map). The preview card follows a copy only in
clipboard-only mode. **On this machine it is `top_right` with a 3s timeout**
(`screenSnip.previewCorner`/`previewTimeout` in the live config, not the shipped
`bottom_left`/2). The notification stack and the clipboard toast share that corner, so its
height on screen varies.

**ydotool, three traps, all hit in this row.**
- `mousemove -a` is not absolute. It jumps to (0,0) and then moves relatively, which is
  also where the 2× factor comes from. **With a button held, the jump is part of the
  drag**: a 4px "wobble" done with `-a` read as a 960px drag and cropped 4×2. Use
  `-a` only to position, and relative `mousemove -x/-y` while pressed.
- Two targets whose halves round to the same integer (`960` and `961`) are the same
  move, so no motion is sent. A surface that mapped under the pointer gets no enter
  until the pointer really moves, and without a real move there is no `positionChanged`,
  so no target is picked. The click then does nothing, and that is correct.
- A card that slides in under a still pointer gets no enter either. Move onto the card
  *after* it has settled. The hover then holds its timeout, which doubles as proof the
  pointer is on it: if the card outlives its timeout, the pointer is there. **Check
  before pressing.** A press-drag aimed at the wrong corner went into Obsidian's file
  tree three times during this row. The vault was checked afterwards (no file modified,
  nothing moved).

**Screenshots are redacted.** Both shots are pixelated except the selector's own chrome
(toolbar, guide, one target's border), because the frozen screen under it was a personal
Obsidian vault. The same redacted after-shot is what went to agy.

## What was wrong

1. **An empty selection ran anyway.** `snip()` warned, dismissed and carried on: there was
   no `return`. A two-file probe (`qs -p`, no windows) settled what happens next. After the
   Loader destroys the window the function keeps running. `execDetached` fires, but a
   handler declared in the parent file (`onPreviewSnip`) does not. magick reads
   `-crop 0x0+X+Y` as "from here to the corner" (measured on an 800×600 image: 700×500
   from +100+100). So a right-click on bare desktop opened the annotator on that crop, OCR
   and QR read it, and Search uploaded it to uguu.se. The default left-click copy was
   saved only by its handler dying. Now the selector stays open and nothing runs. Live:
   an empty click with the clipboard holding a sentinel left the sentinel, no preview, and
   the selector up.
2. **Click versus drag was exact equality.** A one-pixel wobble made a 1×1 crop instead of
   taking the window. `Qt.styleHints.startDragDistance` (10 here, probed) is latched per
   press. Live: a 4×2 wobble while pressed took the whole window, 1916×974.
3. **Invisible targets.** The lookup searched layers and windows whatever the config said.
   `layerRegions` also fed `filterWindowRegionsByLayers`, which drops a window that
   overlaps *any* top layer by even a pixel. `hyprctl layers` here shows a 1×1
   `quickshell` surface at (1919,1017) on the top layer, so any fullscreen window was
   untargetable with layers off. Layers that are off are not computed, and windows are
   only looked up when drawn.
4. **Screen clamp.** It slid an off-screen target back in (`min(x, W - w)`) instead of
   cutting it, so a padded window at the left edge took a strip of whatever was right of
   it. It intersects now (swept in the check).
5. **No enter, no exit.** The Loader was bound to the request. Latched now as in the
   cheatsheet, released by the fade reaching 0. A new request gets a new instance, because
   `retrigger` relies on the fresh instance's `pidof` check to stop a recording. Measured:
   the layer is gone 158ms after Esc and 183ms after a snip (fade `elementMoveExit`
   130ms, plus one `hyprctl` poll). The window is passive during the fade (empty mask,
   no keyboard, `MouseArea` off).
6. **`signal closed()` collided with QsWindow's own `closed`.** Only the reload log said
   so (`qt.qml.invalidOverride ... Duplicate signal name`). Renamed `fadedOut`, and the
   check refuses `closed`.
7. **Binding loop on every open** (`modeIndex`, `OptionsToolbar.qml:26`). It came from the
   two `Synchronizer`s. It is a plain binding in and a signal out now, and the reload plus
   five opens later the log has no binding loop. Live: switching to Circle and drawing a
   loop took its bounds plus padding (182×166).
8. **Types.** `contentRegionOpacity` was `property bool`, so the config's 0.8 was drawn at
   1.0. Content targets are at 0.8 now, which is visible in the after-shot.
9. **Cost.** A screen-sized `layer.enabled` under the circle's `CurveRenderer` shape is
   gone. The `DashedBorder` outline (a `Canvas`, repainted and re-uploaded at selection
   size on every pointer move) is now a `Rectangle` border. The infinite 1200ms pulse on
   the recording border is gone too; the bar's `RecordIndicator` says it is recording.
10. **The toolbar sat on the frozen dock** and read as part of it (`shot-before.png`). It
    sits 8 above Hyprland's `reserved` bottom band now. Measured in the after-shot: toolbar
    bottom at y≈1008, dock pill top at y≈1018, band top at 1018.
11. **Preview card.** It left on the enter spec. Exit is `elementMoveExit`, assigned in the
    `x` binding the way the Fast Pair card does it, and the dodge is on `elementMove`. It
    swipes away like the other two corner cards. Live: released 344px after a
    press on the held card, unmapped 179ms later, temp crop deleted.

`tools/check-region-selector.py`: seven checks, and each fails against the pre-row tree
(`python3 tools/check-region-selector.py <git-archived HEAD>`).

**agy vision** (`gemini-3.1-pro-high`, `--mode plan`). It needs **absolute paths** in the
prompt and no `--add-dir`: with relative paths its reads resolve outside the one
`read_file` rule in `~/.gemini/antigravity-cli/settings.json` and headless mode denies
them. Three findings, all checked against the unredacted pixels, and all wrong: the
toolbar "overlaps the dock" (10px clear), the FAB is "flush with the tabs" (8px gap), and
the guide "has no pointed corner" (it does). The first two are the redaction plus a real
observation: the toolbar's `colSurfaceContainer` pill barely separates from the scrim, and
its shadow is invisible on it. That belongs to the shared `Toolbar`, so it went in
`FINDINGS.md`.

## For the cohesion pass (60fps)

- **The selector's fade in** (`elementMoveFast`, whole window). The frozen frame
  cross-fades over a live screen that is nearly identical, so what is seen is the scrim
  arriving. Watch for a video under it, which is the one case where the two differ.
- **The fade out** (`elementMoveExit`) after a snip, over the frozen frame. It is the most
  frequent motion in the surface. Watch whether 130ms reads as a release or as lag before
  the preview card slides in.
- **The toolbar's rise** is unchanged (`elementMove`), but it now ends above the reserved
  band, not at the screen edge.
- **Targets fading in** as content detection lands, and on each Rect/Circle switch.
- **The preview card's exit** on `elementMoveExit`, and its swipe. It should feel identical
  to the clipboard toast and Fast Pair card thrown.

## Deliberately not done

- **Recording's Select → Post change still cuts.** The frozen frame has to go on the first
  frame so wf-recorder sees the live screen. The scrim, toolbar and guide go with it.
  Fading them separately was possible and judged not worth a second state.
- **`DashedBorder` itself** stays a `Canvas`: four other callers, two of them vendored. Its
  cost only matters when resized per frame, which was this surface's use.
- **The screen translator** copies this toolbar's placement *and* its `Connections` hack
  (`ScreenTranslatorPanel.qml:136-142`). It should follow this row's shape in its own row.
- **The cursor guide does not flip** at the right or bottom edge. Its hint can run off
  screen there for its two seconds. Flipping means flipping the pointed corner too, and
  the collapse animation changes the width that decides the flip, so it would jump
  mid-collapse.
- **No action picker inside the selector.** Pressing another region keybind while it is
  open already switches the action (`action` is a live binding), and the guide re-shows
  its hint.
- **Multi-monitor** is unmeasured (one screen here). Each screen has its own latch.
