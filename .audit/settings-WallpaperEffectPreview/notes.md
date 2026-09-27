# settings-WallpaperEffectPreview — notes

- Reached only through Background → Wallpaper effects. It has no page of its own.
- qmllint warns `Cannot assign binding of type QObject to QQuickItem` on
  `source: glassStage.item ?? blurStage.item ?? thumb`. That is `Loader.item` typing. It
  is not a runtime error and was already there.
- If the effect cards ever grow past ~20, cache one filtered thumbnail per card instead.
  Three live passes each is where DESIGN.md 8 starts to bite.
