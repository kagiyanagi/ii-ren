# ii-background-root — brief

Covers the three top-level files of `modules/ii/background/`: `Background.qml`,
`WallpaperEffects.qml`, `WeatherEffects.qml`. The 122-file `widgets/` tree under them
is out permanently (`DECISIONS.md` 3).

**Purpose.** The desktop itself — the wallpaper plane and everything drawn on it. Nobody
comes *to* this surface; they look past it at their windows. Its job is to be the thing
the rest of the shell floats over and never to pull the eye.

**Primary action.** None, and that is the point. The two things it accepts — a right-click
for the desktop menu, a dropped file for the wallpaper or the shelf — are both invisible
until asked for. Everything else here is a backdrop that has to stay out of the way.

**Hierarchy.** Not a stacking of controls but a stack of **planes**, and the whole design
problem is that the user reads them as one surface:

1. the wallpaper (`wallpaper`, parallaxed, optionally shape-masked and post-processed)
2. the widget canvas (`WidgetCanvas`, parallaxed at its own `widgetsFactor` rate)
3. subject depth (`subjectLayer`, welded to the wallpaper's pixels)
4. the weather shader (`WeatherEffects`, drawn over the finished plane)

Only one element is ever allowed to demand attention: the drop hint, and only while a
drag is over the desktop.

**Reference.** Android 16's live-wallpaper surface — parallax on workspace change, a zoom
behind the launcher, AOSP `weathereffects` on top, subject segmentation behind the clock.
The drop hint is Android's drag-and-drop target highlight: one centred card naming what
the drop will do.

**Interaction.**

- **The planes move as one.** Any transform applied to one plane must be applied to the
  others on *the same spec*, or they slide against each other and the desktop comes apart.
  `WeatherEffects` already mirrors `wallpaperItem.scale` verbatim and says so; the widget
  canvas already parallaxes on `elementMove`. The wallpaper itself is the odd one out and
  must join them. `widgetsFactor` is allowed to change how *far* a plane travels — never
  how long it takes.
- **Parallax** (workspace change, sidebar open) is position on a screen-sized surface:
  `Appearance.animation.elementMove`, the same spec the widget canvas uses. Overshoot is
  wanted and is what the shell does everywhere else.
- **Wallpaper geometry** (`width`/`height`, when a new image's dimensions arrive) changes
  in the same instant as `x`/`y`, because `movableXSpace` is derived from it. Same spec,
  for the same reason — a slower size than position exposes the void at the wallpaper's
  edge mid-swap.
- **The lock zoom** (`blurLoader.scale`) is a screen-sized plane on the default spatial
  curve; it takes that curve's own duration, not a hand-picked one under it.
- **The drop hint** is the file's one appearing surface, so 2.5 applies in full: enter on
  default spatial with opacity on effects, exit on fast effects at about half. Transform
  origin is `Item.Center` **deliberately** — it is pinned to the middle of the screen and
  the drag it answers can be anywhere, so there is nothing else to grow out of.
- **Ambient motion is exempt from the UI ladder and says so.** `WeatherEffects`'
  3000ms `InOutSine` intensity ramp is AOSP `WeatherEngine.AUTO_FADE_DURATION_MILLIS`
  transcribed, an order of magnitude slower than any UI move, and it already carries that
  citation. Leave it.

**Edge states.**

- **No wallpaper / `magick` missing** — `getWallpaperSizeProc` returns nothing; the last
  known size is kept rather than dividing by `NaN`. Already handled.
- **Wallpaper the same size as the screen** — parallax has nothing to pan; it gets the
  same zoom an oversized one gets. Already handled.
- **Every window in one workspace chunk** — `(id - lower) / range` is `0/0`. `NaN` passes
  straight through `Math.max`/`Math.min` and lands in the wallpaper's `x`, which puts the
  whole plane nowhere. **Broken; the clamp has to be `NaN`-safe at the source.**
- **No active workspace** on a monitor — `undefined - lower` is the same `NaN`, same path.
- **Work-safety triggered** — wallpaper blanked, widget canvas squared up, solid primary
  wash. Already handled.
- **Drag carrying nothing usable** — the `DropArea` refuses so the drag falls through
  instead of being swallowed, and no hint is drawn. Already handled.

**Cost.** The effect budget is already tight and stays as it is. `Background.qml` keeps
one `layer.enabled` + `OpacityMask` (the shape mask, config-gated), one `GaussianBlur` +
`ShaderEffectSource` (the lock blur, loaded only while locked and baked once);
`WallpaperEffects` keeps its Loader-per-stage chain that freezes to a single textured
quad; `WeatherEffects` keeps its shaders, which are the effect. Nothing is inside a
repeating delegate. What this row *removes* is cheaper than any of it: `isCovered` re-ran
`HyprlandData.windowList.some(...)` on every window event and was read by nothing.

**Delete.** Seven properties and two `Behavior`s that nothing reads:

- `activeWorkspaceId` → `isCovered` — a window-list scan per window event, zero readers.
- `shouldBlur` → `dominantColor` → `dominantColorIsDark` → `colText` + its colour
  `Behavior` — `dominantColor` is commented "to be changed" and never is; the chain's only
  consumer is `colText`, whose only consumer is nothing. The live copy of this idea is
  `AbstractBackgroundWidget`'s, in the widgets tree.
- `scaleAnimated` + its `Behavior` — an orphaned twin of `Overview.qml`'s property of the
  same name. `wallpaperItem.scale` computes its own.

Also deleted: the duplicated six-line parallax expression in `valueX`/`valueY`, which
collapses to one guarded `workspaceProgress` that both read.

**Out of scope.**

- `widgets/` (122 files) — vendored, rsynced with `--delete`.
- `Overview.qml`. Its own `scaleAnimated` runs on `elementMoveFast` (200ms, effects) while
  the desktop plane behind it zooms on `elementMoveEnter` (500ms, spatial) — the two are
  out of register and the overview's is the one that is wrong by 2.1. Retiming another
  row's surface without watching it is law 10; recorded in `notes.md` for `ii-overview`.
- `lock.blur.*` defaults and the lock screen itself (`ii-lock`).
- The shape-mask `MaterialShape` recipe and `FlutedGlass`/`WallpaperFilter`, which are
  `modules/common/widgets` and were done in the `cw-*` rows.
