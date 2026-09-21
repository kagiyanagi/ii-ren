# ii-dock — notes

Ran lane 1 end to end in one session rather than splitting the row. It is 3,860
lines against the 2,500 split rule, and splitting is the right call *before* the
reading is paid for — the rule exists so no context holds two surfaces. By the
time the size was visible the whole surface was already read, so a split would
have bought a second session that re-reads the pack and nothing else. The change
list was scoped instead, and what was left is at the bottom of this file.

## What was measured, not assumed

- **Every app icon was paying three offscreen passes, and no gate could see
  one of them.** `DockIcon` ran a `Desaturate` *and* a `ColorOverlay`
  (`monochromeIcons` defaults to `true`), and `DockAppButton` added a blurred
  `StyledDropShadow` on top. `check-effect-budget.py` finds a nested effect by
  reading a `Repeater` or `delegate:` block **inside one file**, and every dock
  delegate is its own file — so all three were invisible to it, and the surface
  came through the whole audit reading as clean. Thirteen pinned apps plus
  running ones is ~40 framebuffers for a strip of 39px icons. Now one
  `MultiEffect`, as a `layer.effect` so there is no second `ShaderEffectSource`,
  and only while monochrome or dim-inactive is on. `tools/check-dock.py` states
  the ceiling per delegate file, because the generic gate still cannot.
- **The hover scale works, and is the whole feedback.** Checked live before
  deleting the shadow: `ydotool mousemove` onto an icon, `grim` the same 60px
  crop hovered and not, `magick compare` → the icon is measurably larger when
  hovered. Launcher3's taskbar icons carry no elevation of their own, the dock's
  sit on a solid `colLayer0`, and DESIGN.md 3.3 names the scale as the recipe.
  So the shadow was a third framebuffer per delegate buying nothing.
- **The monochrome look survives the collapse.** `Desaturate(0.8)` +
  `ColorOverlay(colPrimary @ 0.1)` → `saturation: -0.8` +
  `colorization: 0.1`. `magick compare` on one icon before/after: RMSE 3.4%,
  and essentially all of it is the removed shadow. Colorization tints against
  the icon's own luminance rather than flat-blending, which at one tenth is
  below the noise.
- **Two option combinations were quietly broken and now are not.** With
  monochrome on, `dimInactiveIcons` did nothing at all — the `Loader` holding the
  mono path had no opacity binding, so a not-running app drew at full strength.
  With monochrome off and dim on, the desaturated copy drew *over* the coloured
  original, both at 0.55. One effect with `saturation` and `opacity` as bindings
  gives each combination the one thing its name says.
- **Escape cannot close a dock context menu, and a `Keys` handler would be dead
  code.** It is an xdg popup on the dock's layer surface, which takes no
  keyboard focus — the reason `DockFolderPopup` is a separate `OnDemand` panel
  and says so in its first comment. Giving the context menus a keyboard means
  making them panels too. A comment now sits where the next attempt would go.

## Decision 14, closed

`ArrowPopupMotion.qml` is the extraction the `arrowPopup*` token block asked for
— "assembled by each caller", four callers, by hand. This row had two of them
and they had drifted in opposite directions: `DockFolderPopup` grew an inline
bezier and six literal durations, and `DockContextMenuBase` had no exit at all —
one `Behavior on scale` and one `Behavior on opacity`, both on `elementResize`,
a spatial spec, out of `transformOrigin: Item.Center`. Both now call the shared
widget and both pivot on the dock's edge.

`DesktopMenu`, `HermesContextMeter` and `HermesApprovalModeMenu` still assemble
it by hand. They are each other rows; the `Appearance.qml` comment now points at
the widget rather than at them.

## Driving this surface

The dock has no `IpcHandler`. It is on screen whenever `dock.enable` is true, and
`pinnedOnStartup` is true on this machine, so `grim -g "0,940 1920x140"` is the
whole shot. To open the rest:

- **`ydotool mousemove -a` is 2× off here**, the same as the cheatsheet row
  found: to land at `(X, Y)` pass `-x X/2 -y Y/2`. Confirm with
  `hyprctl cursorpos`, never assume it landed.
- Context menu: move onto an icon, `ydotool click 0xC1`.
- Folder card: move onto the folder button, `ydotool click 0xC0`.
- Dismiss either by clicking anywhere off it — the focus grab handles it.
- `SMOKE_WANT="quickshell:dock" tools/audit/smoke.sh` is the boot gate;
  the default `quickshell:bar` says nothing about this surface.

## Left alone on purpose

- **`DockMediaWidget`'s four-effect stack.** `layer.enabled` + `OpacityMask` on
  the card, a `MultiEffect` blur on the overscanned art, another `OpacityMask`
  on the art tile, plus the card shadow — and because `WaveVisualizer` repaints
  inside the card's layer, that mask re-composites on every Cava frame. It is
  one widget, not a delegate, so it is the cheapest of the three costs; undoing
  it means rounding without a mask (`ClippingWrapperRectangle`) and re-testing
  the blur and the visualizer against it. Its own row.
- **`DockPreviewPopup`'s per-delegate `OpacityMask`.** Already in
  `check-effect-budget.py`'s `KNOWN`, and it rounds a live `ScreencopyView`
  there is no cheaper way to round.
- **`DockSeparator`'s `Line` and `Dot` styles.** Decision 10 already ruled: the
  default is `Empty`, the styles stay for a config that explicitly chose one.
  This machine's config chose `Line`, which is why they are in `shot-after.png`.
- **The unqualified `root` in `DockListView`, `SectionSeparator` and
  `DockAppIcon`.** All three read `root.isVertical` / `root.buttonSize` out of
  the *caller's* scope — dynamic scoping that works only because every caller
  happens to be inside `DockContent`. This is the shape `ii-bar-chrome` found
  silently resolving to `undefined`. It works today; unpicking it touches every
  delegate and wants its own diff.
- **Teaching `check-effect-budget.py` about delegates that live in their own
  file.** It needs the reverse-dependency map `pack.py` already builds, which is
  a tooling row, not a surface row. `tools/check-dock.py` covers this surface's
  instance; every other surface with file-delegates still has the blind spot.

## For the cohesion pass (60fps)

- **The context menus' enter and exit.** They had neither before — one spatial
  `Behavior` ran both directions out of the centre. They now pop out of the
  dock edge on `arrowPopupScale` → `arrowPopupOvershoot` → settle and leave on
  `emphasizedAccel` with the fade held. This is the most-opened of the dock's
  popups and the change is the largest in the row; a still frame proves nothing.
- **The icon hover and press.** 300ms `emphasizedDecel` and the 90ms squish are
  now `Appearance.animation.iconHover` / `iconPressSquish` — same numbers,
  but `iconHover` also gained `alwaysRunToEnd: false`, which the hand-written
  `NumberAnimation` did not have. A hover flicked across the strip should now
  reverse rather than finish (DESIGN.md 2.7).
