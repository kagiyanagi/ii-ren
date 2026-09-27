# settings-BarConfig — notes

- Opens with `II_SETTINGS_PAGE=bar qs -p ~/.config/quickshell/ii/settings.qml`.
- Quick → Bar position is a second copy of this page's position picker. It never had the
  displayMode write, and it does not need one now that the write is gone.
- `componentMap`/`scrollTo` is kept: nothing in this repo calls it, but it is the
  obvious hook for a bar widget's "open its settings".
