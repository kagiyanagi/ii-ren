# settings-HermesConfig — notes

- Opens with `II_SETTINGS_PAGE=hermes qs -p ~/.config/quickshell/ii/settings.qml`. The
  gateway was up for the shot, so these are live values.
- A vault source's `ConfigSwitch` called `HermesService.setVaultSource` from
  `onCheckedChanged` unguarded. That fires while the row is built, and again on every
  refresh that rebuilds the `Repeater`, so each source's own state was sent back to the
  agent. It is gated on a real change now.
- The dialog's exit was not driven: this machine has no vault items to remove.
  `WindowDialog` is `visible` while its card height is above 0, and the latch releases on
  `!visible && !show`, the same rule `SidebarDashboardContent.ToggleDialog` uses.
- Reasoning effort stays a free-text field. The set of values the agent accepts is not
  known from this side.
