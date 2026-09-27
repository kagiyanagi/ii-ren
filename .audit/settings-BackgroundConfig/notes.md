# settings-BackgroundConfig — notes

- Opens with `II_SETTINGS_PAGE=background qs -p ~/.config/quickshell/ii/settings.qml`.
- Search reads 3 sections here: Parallax, Wallpaper, and the `TargetedSection` component
  body. The shape, depth, effects, weather and glass sections are instances of components
  built on `ContentSection`, so `SearchRegistry.indexQmlFile` never sees their titles.
  Making them searchable means teaching the parser component instances, or listing extra
  keywords.
- The shape swatches were not screenshotted: the shape mask is off on this machine and
  they only show with it on.
- `check-design.py` in bare mode still flags `radius: 50`/`radius: 9` in the blur-style
  model. Those are blur radii (the ROM values), not corner radii.
