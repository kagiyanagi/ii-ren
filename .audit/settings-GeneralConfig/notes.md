# settings-GeneralConfig — notes

- Opens with `II_SETTINGS_PAGE=general qs -p ~/.config/quickshell/ii/settings.qml`.
- This file is statically indexed by `SearchRegistry` (it parses `ContentSection` blocks
  out of the text), so the section merge changes which titles search lists. "Screen
  Translator" and "Date" are subsection titles now, and subsection titles are indexed too.
- Battery → Full warning goes to 101, which means off. The spin box cannot say so. A
  `ConfigSpinBox` with a display-text hook would fix it, and that is a shared-widget change.
- Autostart rows come from a `Repeater`, so they sit bare rather than carded. See
  `settings-AdvancedConfig/notes.md` on `Repeater` and `ContentGroup` runs.
