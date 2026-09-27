# settings-AdvancedConfig — notes

- Opens with `II_SETTINGS_PAGE=advanced qs -p ~/.config/quickshell/ii/settings.qml`. The
  Fonts section is below the fold; `shot-after-fonts.png` was taken by wheeling the page
  with ydotool (`II_SETTINGS_HIGHLIGHT` only opens sub-pages, it does not scroll).
- Search index was 6 (Services); it is page 10.
- The seven `FontField`s are written out rather than repeated: `ContentGroup` walks
  `column.visibleChildren`, which includes a `Repeater` item, reads it as a bare row and
  splits the card run around it. Layouts skip the Repeater and `ContentGroup` does not.
  This holds for every settings page, so wrap repeated rows some other way.
- `appearance.toggleWindowRounding` stays declared in `Config.qml` so existing config
  files keep loading; only the switch is gone.
- The shipped default names in `fontRoles` must match `Config.qml`'s font defaults. Nothing
  checks that.
