# settings-WidgetsConfig — notes

- Opens with `II_SETTINGS_PAGE=widgets qs -p ~/.config/quickshell/ii/settings.qml`.
- **"Show widgets only in one monitor" and its picker did nothing.** Nothing read
  `background.widgets.showOnlyOnSingleMonitor` or `targetMonitor`. `Background.qml` is ours
  (only `widgets/` is vendored), so the fix is one `visible` binding on its `WidgetCanvas`:
  the canvas shows only on the picked screen, or on the first screen when none is picked.
  Not verified on two monitors, since this machine has one. On one monitor the canvas
  stays visible, which was checked.
- Clicking in the settings app with ydotool needs a one-pixel relative nudge after the
  absolute move, or the first click does not land. `/tmp`-style driver used: absolute
  move, `mousemove -x 1 -y 0`, then `click 0xC0`.
- `DirectionalGaussianBlur.qml WARNING: Maximum of blur radius (16) exceeded!` comes from
  vendored widget previews, before and after.
- The two `Connections` the design check flagged: the extensions one is guarded with
  `?? null`. The other targets the settings window's `root`, which exists before any page
  does.
