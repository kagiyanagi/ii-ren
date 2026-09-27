# settings-QuickConfig — notes

- Opens with `II_SETTINGS_PAGE=quick qs -p ~/.config/quickshell/ii/settings.qml`.
- The settings app is its own process, so `HyprlandComfortView` and `HyprlandReadingMode`
  here are **second instances** of those singletons. The page's switches and spin boxes
  called `toggleManual`/`toggleAutomatic`/`togglePaperTone`/`setIntensity` from their change
  handlers with no guard. HyprlandConfig's comment says those handlers fire while the
  control is built, so with Comfort View on, opening Quick could run `enable()`, and with it
  a shader rewrite and a `hyprctl reload`. Every call is gated on a real change now. This
  was not measured: the page was not watched for a reload before the fix.
- `sourceSize: (512,512)` was the JS comma operator. It is `512`, which QSize refuses, so
  the thumbnails loaded at full size. qmllint found it.
- Nothing here was ever searchable: this is page 0, and `ContentSection` skipped a falsy
  index. That is fixed in the shared search commit.
- `appearance.defaultBorderRadius` and `hyprland.defaultHyprlandLayout` are read only by
  this page, as the values Sharp / Default restore. That is a legitimate use, not a dead key.
