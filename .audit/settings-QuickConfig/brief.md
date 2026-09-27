# settings-QuickConfig — brief

**Purpose.** The handful of choices most people change first: wallpaper and palette,
eye protection, and how the bar and screen corners look.

**Primary action.** Pick a wallpaper from the favourites carousel.

**Hierarchy.**
1. **Wallpaper & Colors** — carousel, light/dark, palette grid, Transparency (unchanged).
2. **Eye protection** — one section with three subsections: Night light (automatic night
   light, automatic dark mode, from/until), Comfort View and Reading Mode. These used to
   be three sections, pulled together with `Layout.topMargin: -25` each. The name is the
   sidebar dialog's, which holds the same effects.
3. **Bar & screen** — position, style, screen corners, rounding style, background style,
   layout (unchanged).
4. The config-file notice.

**Reference.** Android 16 Settings → Display, with Eye comfort and Bedtime grouped.

**Interaction.** The carousel widens while a card is held. That is one `widened` flag and
a `Behavior` on `elementMove`. It used to be two hand-timed 450ms OutCubic
`PropertyAnimation`s started from the carousel's handlers.

**Edge states.** No favourites: the star and hint (unchanged). The palette buttons are
disabled with a custom scheme (unchanged).

**Cost.** Unchanged. The favourites thumbnails now get the 512px `sourceSize` they asked
for.

**Delete.** The four negative top margins, the notice's -20, an unused `Process`
(`randomWallProc`, nothing started it), an unused `currentIndex` property and its
GraphicalEffects import, and a `console.log` on every layout pick.

**Out of scope.** `Carousel`, `ColorPreviewGrid`, the eye-protection services.
