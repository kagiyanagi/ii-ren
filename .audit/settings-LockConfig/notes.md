# settings-LockConfig — notes

- Opens with `II_SETTINGS_PAGE=lock qs -p ~/.config/quickshell/ii/settings.qml`.
- The page declared search index 12 (About) and is page 9. Fixed in the shared search
  commit, `tools/check-settings-search.py`.
- `ConfigNavRow` (new, `modules/common/widgets/`) replaced four hand-copied sub-page rows:
  this one, Advanced's two and Interface's notification history. None of the copies had
  `wantsCard`, so each sat bare under a carded run.
- `unlockKeyring` and `requirePasswordToPower` are left enabled with Hyprlock on. Neither
  was traced through the Hyprlock path.
