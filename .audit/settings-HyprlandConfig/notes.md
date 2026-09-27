# settings-HyprlandConfig — notes

- Opens with `II_SETTINGS_PAGE=hyprland qs -p ~/.config/quickshell/ii/settings.qml`. The
  shot is the top, and the Appearance tail wheeled into view.
- Search index was 7 (Extensions); it is page 8.
- Input → Cursor (theme combo and size) and Advanced → Cursor (a sub-page with previews)
  set the same thing through `CursorTheme.setCursor`. Keep one if the pages are
  reorganised; this row did not choose.
- The layout combo only writes on `onActivated`, and switches and spin boxes go through
  `put()`, so opening the page wrote nothing to Hyprland (unchanged).
