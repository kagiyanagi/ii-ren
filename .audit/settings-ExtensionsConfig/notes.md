# settings-ExtensionsConfig — notes

- Opens with `II_SETTINGS_PAGE=extensions qs -p ~/.config/quickshell/ii/settings.qml`.
  Extensions are off here. `shot-after-enabled.png` came from a sandbox:
  `XDG_CONFIG_HOME=/tmp/sbx/cfg` holding a symlink to `~/.config/quickshell` and a copied
  `illogical-impulse/` with `extensions.enable: true`. The link button was clicked with
  ydotool. `config.json` and `plugins.json` were md5-checked before and after every run,
  real and sandbox: no writes on load. See `ii-settings/notes.md` for why that matters.
- **Do not `pkill -f` a pattern that is in your own command line.** It kills the shell
  running the command (exit 144). Kill by pid, found through `/proc/<pid>/environ`.
- Turning extensions on used to fetch nothing: `Component.onCompleted` was the only
  caller of the refresh, so the browse list stayed empty until the page was reopened. It
  is `activate()` now, called from both.
- `GroupButtonWithTextField` (its only caller is this page) declared
  `signal textChanged(string)` over the button's own `text` property. Qt logged "invalid
  override" on every load. It is `textEdited` now. `textFieldText` also never reached the
  field, so clearing it after an install left the URL in the box. It is written back now.
- Search index was 8 (Hyprland); it is page 7.
- Not verified: a real install from a URL (needs a repo to clone).
