# ii-screenCorners — brief

**Purpose.** Make a square panel read as a rounded display, on every monitor, and let the
top (or bottom) corners open the sidebar on their side, with scroll for brightness and
volume.

**Primary action.** None for the rounding: it imitates hardware, it is not UI. For the hot
corner, toggling the sidebar on that side. Scroll is secondary and must stay invisible
until used (the OSD is its feedback).

**Hierarchy.** Nothing here should be noticed. The corner is the bezel's black
(`m3colors.m3scrim`), exactly `rounding.screenRounding`, and click-through. The hot corner
draws nothing; `visualize` is a tuning aid, not a state.

**Reference.** SystemUI's `ScreenDecorations`: the rounded-corner overlays Android draws on
panels whose corners have to be faked. Black, static, not touchable, one set per display,
no motion. Hot corners have no Android counterpart; the model is GNOME's Activities
corner, which fires once per arrival and uses the thing it opens as its feedback.

**Interaction.**
- Rounding: the shell adds no motion, on purpose. `ScreenDecorations` has none. The one
  visible change, the mode-2 hide, is a map or unmap, and Hyprland already animates that:
  `hyprland/rules.lua` gives the `quickshell:screenCorners` namespace `popin 120%`. A
  shell-side fade would need a latch that keeps an Overlay surface over a fullscreen window
  for its duration.
- Hot corner: a click toggles. Hovering only ever *opens*, never closes. That covers both
  `clickless` (enter) and the edge trigger (`clicklessCornerEnd`), which fires once when
  the pointer arrives at the side edge rather than on every motion event after that, and
  only while `clickless` is off. The settings page already greys it out in that state; the
  code has to agree. (Decided while building. The first draft toggled on hover, which is
  only safe while the opened sidebar's focus grab hides the corner, and a pinned sidebar
  takes no grab.)
- For a moment after this side's sidebar closes, hover is ignored. Closing it ends its
  focus grab, and a pointer resting in the corner comes back as a fresh enter that looks
  exactly like an arrival. The window is `Qt.styleHints.mouseDoubleClickInterval`, the
  platform's own "same gesture" window, not an invented number.
- Scroll: brightness on the left, volume on the right, and the OSD closes when the pointer
  moves away. Unchanged.
- Transform origin: not applicable, nothing moves.

**Edge states.**
- *Several monitors*: each monitor gets its own four corners, and mode 2 hides them for a
  fullscreen window on that monitor only.
- *Rounding off (0) or wrapped (3), hot corner on*: the hot corner still exists. It is the
  same window, so it must not depend on the rounding.
- *Sharp mode*: the radius is 0, so there is nothing to paint and no surface is needed
  unless the hot corner needs one.
- *Fullscreen*: the hot corner is off on that monitor. Unchanged. If you leave fullscreen
  with the pointer parked in the corner, the first nudge opens the sidebar. That is
  accepted, because it cannot be told apart from an arrival (`notes.md`).
- *One monitor, shipped config*: the pixels stay the same.

**Cost.** One static `Shape` per corner, four per screen. `RoundCorner`'s `layer.enabled`
belongs to the shared widget (16 callers) and stays. Its content never changes, so it is
drawn once.

**Delete.** `property var screen`, which shadows `PanelWindow.screen` and swallows
`screen: modelData`. `brightnessMonitor` and `activeWindow`, which nothing reads. The
`actionForCorner` map, where one `isLeft` branch does the same job. The two-stage workspace
filter, replaced by one `some()` in the dock's form. The unused imports.

**Out of scope.** `RoundCorner` itself. `WrappedFrame`. The settings page. Which panel a
corner opens under `sidebar.position` `inverted`/`left`/`right`: the bar's side click
areas use the same left→policies, right→dashboard mapping, and changing one without the
other splits two ways of opening one panel (see `notes.md`).
