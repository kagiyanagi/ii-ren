# settings-ServicesConfig — notes

- Opens with `II_SETTINGS_PAGE=services qs -p ~/.config/quickshell/ii/settings.qml`.
- **Screenshots of this page leak.** The Calendar field shows the user's private iCal
  URLs (with their email), and Weather shows their city. `shot-before.png` was cropped
  above the Calendar field, and `shot-after.png` is the save-paths stretch. Check any new
  shot before committing it.
- `editingFinished` is also what fires on focus-out. A field that is edited and then
  left by closing the window may not commit. That is the same trade the Hyprland and Quick
  pages' fields already make.
- Search index was 5 (Interface); it is page 6.
- General → Policies → Hermes and Hermes → "Show Hermes in the sidebar" both write
  `hermes.enable`. Both are kept: one is the feature-flag overview, the other the page's
  master switch.
