# ii-background-root — notes

Ran **lane 1**, not the lane 2 the queue row says, for the same reason `ii-altTab` did:
no agy tier was up in this session.

## The screenshots are not evidence here — read this instead

Both shots are of an occupied desktop, and a bare one would not have helped. Nothing this
row changed is visible in a still frame:

- three of the four changes are **motion** (parallax timing, the lock zoom, the drop hint's
  enter/exit),
- one is a **`NaN`** that needs a specific workspace layout to reproduce,
- and the rest is **dead code** that was already drawing nothing.

The machine was in use while the row ran (the two shots are minutes apart and the browser
has navigated between them), so driving the desktop any further to stage a cleaner frame
was not worth the interruption. `tools/check-desktop-parallax.py` is the real evidence for
the arithmetic; the list below is the real evidence for the motion, and it is the cohesion
pass that collects it.

## For the cohesion pass — what to watch at 60fps

1. **Workspace-switch parallax.** The wallpaper was on a hand-rolled `600ms OutCubic`
   while the widget canvas over it was on `elementMove` (500ms, `expressiveDefaultSpatial`,
   which overshoots). Both are `elementMove` now, so the two planes should arrive together
   and overshoot together. Watch the clock widget against the wallpaper texture under it
   during a `Super+1` → `Super+2`: any relative slide is a regression.
2. **Sidebar-open parallax.** Same two planes, same specs, shorter travel
   (`sidebarOffsetX` is ±0.15). Cheaper to watch than a workspace switch.
3. **Wallpaper swap.** `width`/`height` were on `800ms` while `x`/`y` were on `600ms`, and
   all four change in the same instant because `movableXSpace` is derived from the size.
   All four are `elementMove` now. Watch the wallpaper's edge during a change from the
   selector: the void behind the plane must never show.
4. **Lock zoom.** `blurLoader.scale` ran a 500ms bezier over 400ms; it now gets that
   curve's own duration, and `lockBlurSettle` follows it so the blur is still live for the
   whole zoom. 400 → 500ms is the one timing here that got *slower*.
5. **The drop hint.** Drag an image onto the desktop. It should now grow from 0.9 at its
   centre on the default spatial curve and leave on fast effects at about a quarter of the
   time. **Not verified by driving** — staging a real drag-and-drop needs a drag source.

## Two findings outside this row's files

**`bgRoot.lockAnimationActive` does not exist.** `widgets/media/MediaWidget.qml:29-38` and
`widgets/media/ExpressiveMediaWidget.qml:29-38` both read
`(typeof bgRoot !== 'undefined' && bgRoot.lockAnimationActive) ? lastStaticHeight : ...`,
to freeze their implicit size while the lock animation runs. `bgRoot` — the `PanelWindow`
in `Background.qml` — has no such property, so the ternary always takes the live branch
and those two widgets reflow during the lock animation. The value *is* available: it is
passed into `WidgetDelegate` explicitly as `lockAnimationActive: GlobalStates.lockAnimationActive`.

Deliberately **not fixed**. One line on `bgRoot` would satisfy the probe, but the fix
would be a behaviour change to a vendored tree (`DECISIONS.md` 3) that this session could
not watch — freezing a size is exactly the kind of thing that goes wrong when the flag
sticks — and a re-port could rewrite the probe anyway. Belongs with the re-port, not here.

**Overview and the desktop zoom out of register.** `Overview.qml:79` animates its
`scaleAnimated` on `elementMoveFast` (200ms, *effects* curve) while the desktop plane
behind it zooms on `elementMoveEnter` (500ms, default spatial). Opening the overview moves
two halves of one gesture over durations that differ by 2.5×, and by DESIGN.md 2.1 the
overview's is the wrong one — a scale is spatial. Left for **`ii-overview`**: retiming
another row's surface without watching it is law 10, and this row cannot drive the
overview any more than it can drive a drag.

Background.qml's own `scaleAnimated` — an orphaned copy of the overview's property, read
by nothing — was deleted as part of this row.

## How to open it

It is always on screen; there is no IPC handler. To see it bare,
`hyprctl dispatch 'hl.dsp.focus({ workspace = 9 })'` (an empty workspace) and back.

**`hyprctl dispatch` takes Lua here, not hyprlang.** `hyprctl dispatch workspace 9` fails
with a Lua parse error, and so does the quoted form; the working call is
`hyprctl dispatch 'hl.dsp.focus({ workspace = 9 })'`. Worth knowing for any row that wants
to stage a workspace.

## The checker, and the two ways it nearly did not work

`tools/check-desktop-parallax.py` asserts the parallax lands a finite number and that the
planes name one spec. Two things it got wrong first, both worth not repeating:

- **Python's `min`/`max` are not `Math.min`/`Math.max`.** `min(1, nan)` is `1` in Python
  and `NaN` in JS. Lifting the clamp and evaluating it with Python's builtins sanitised
  the exact value the check exists to catch, and the check passed on broken code. It ships
  with `jsmin`/`jsmax` shims.
- **Transcribing a guard is not testing it.** The first version restated
  `if (id === undefined || range <= 0)` in Python and checked the QML still contained the
  string. Commenting the line out in the QML — leaving the string in a comment — passed.
  It now extracts the condition from the QML and *evaluates* it, so dropping either half
  fails a numeric assertion, and deleting the line entirely fails as "stale".

## Left alone deliberately

- **qmllint's four `unused-imports`** on `Background.qml`, one of them marked
  `//FIXME. remove`. Three are the `widgets.clock` / `widgets.weather` / `widgets.media`
  module imports; whether the registry's dynamic component loads lean on them is not
  something qmllint can see, and the payoff is zero pixels.
- **`WeatherEffects`' 3000ms `InOutSine` intensity ramp.** AOSP
  `WeatherEngine.AUTO_FADE_DURATION_MILLIS`, already cited in the file. Ambient weather,
  not UI motion.
- **`WallpaperEffects`' `settle` (2500ms) / `quickBake` (150ms) timers.** They wait out an
  async bake, not a transition.
- **`wallpaperItem.scale`** — see the overview finding above.
