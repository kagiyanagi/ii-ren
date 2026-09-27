# settings-WallpaperEffectPreview — brief

**Purpose.** Show the current wallpaper through one effect configuration, inside an
effect picker card on Background.

**Primary action.** None; it is a preview inside `BackgroundConfig`'s `EffectCard`.

**Hierarchy.** The image, full bleed in its card.

**Interaction.** None of its own.

**Edge states.** No wallpaper: the `wallpaper` icon in `colSubtext`. It used to be a
`StyledText`, so it drew the word "wallpaper". A video wallpaper previews its thumbnail.

**Cost.** Up to three `ShaderEffectSource`-backed passes per card (blur, glass, filter),
at thumbnail size. There are 18 cards, 9 filters and 9 glass presets, so this is the
heaviest thing on the settings side. It is kept, because the preview is the picker. Every
source is a static `Image`, so the passes render when the image loads and not per frame.
The cards wait for `page.allowHeavyLoads`.

**Delete.** Nothing.

**Out of scope.** `EffectCard` and the effect sections (`settings-BackgroundConfig`).
