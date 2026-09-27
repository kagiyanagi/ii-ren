# settings-InterfaceConfig — notes

- Opens with `II_SETTINGS_PAGE=interface qs -p ~/.config/quickshell/ii/settings.qml`.
- Search index was 4 (Widgets); it is page 5.
- `check-appearance-refs.py` now checks `Appearance.font.{variableAxes,pixelSize,family}.*`.
  Its parser had a bug that hid this level: `property var main: ({` opened a brace it
  never pushed, so the `})` popped the enclosing group, and every later member was
  recorded one level up. Two real misses sit in the vendored concentric clock
  (`font.family.display`) and are named in its `KNOWN` set rather than fixed, because
  the re-port would revert the fix.
