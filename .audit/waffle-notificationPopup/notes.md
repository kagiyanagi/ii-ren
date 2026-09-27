# waffle-notificationPopup — notes

**Opening it.**
- Active under `Config.options.panelFamily: "waffle"`.
- Triggered automatically whenever a notification with `popup: true` arrives in `services/Notifications.qml` (e.g. `notify-send "Title" "Body"`).

**Measured and fixed.**
- **Surface latch & exit grace period:** In `WaffleNotificationPopup.qml`, replaced `visible: (Notifications.popupList.length > 0) && !GlobalStates.screenLocked` with a latch pattern (`property bool mapped: false`) and a one-shot `exitGrace` Timer. When the notification list empties, `exitGrace` runs for `Appearance.animation.elementMoveExit.duration` before resetting `mapped = false`. This guarantees `WSingleNotification`'s dismissal slide-out animation finishes drawing before the layer surface unmaps.
- **Bound component behavior:** Declared `pragma ComponentBehavior: Bound` at the top of `WaffleNotificationPopup.qml`.
- **Keyboard focus safety:** Added `WlrLayershell.keyboardFocus: WlrKeyboardFocus.None` to prevent toast notifications from ever intercepting keyboard focus from active windows.
- **Pinned monitor resolution:** Updated `screen` binding to respect `Config.options.notifications.monitor` when enabled, with fallback to the focused monitor.
- **Dynamic taskbar positioning:** Bound `barAtBottom: Config.options.waffles.bar.bottom`, anchoring `WListView` to `parent.bottom` when the taskbar is at the bottom (Windows 11 standard) and to `parent.top` when the taskbar is configured at the top of the screen.
- **Geometry & anchor resolution:** Removed conflicting `width: parent.width - Appearance.sizes.elevationMargin * 2` on `WListView` while both `anchors.left` and `anchors.right` were set.
- **4dp grid alignment & card width parity:** Standardized `gutter: 12`, `spacing: 12`, and `implicitWidth: 384` on `WListView`. With 12dp margins, the effective notification card width is `384 - 24 = 360dp`, perfectly matching the 360dp card width in Waffle Notification Center.
- **Click-through mask bounds:** Rewrote `popupBounds` height to evaluate to `0` whenever `!hasPopups` or `listview.count === 0`, eliminating the 32dp dead zone where an empty listview previously intercepted clicks.
- **Published stack height contract:** Added `Binding` for `GlobalStates.notificationPopupHeight`. Publishes `0` when notifications are at the bottom or empty (so top-right toast readers do not inset needlessly), and publishes the clamped stack height when top-anchored so overlays shift down without collisions.
- **Model null safety & entrance animation:** Wrapped `Notifications.popupList ?? []` in `ScriptModel` and added an entrance fade `Transition` using `Appearance.animation.elementMoveFast.duration` and `Looks.transition.easing.bezierCurve.easeIn`.

**Automated verification.**
- Created `tools/check-waffle-notificationpopup.py` verifying bound pragma, exit latching, screen resolution, keyboard focus, anchor behavior, mask geometry, published height contract, and 4dp grid metrics.
- Ran `python3 tools/check-waffle-notificationpopup.py` (passed).
- Ran `python3 tools/check-notification-popup.py` and `python3 tools/check-waffle-notificationcenter.py` (all passed).
- Ran `python3 tools/check-mask-regions.py` (passed).
- Ran `python3 tools/check-design.py --diff` (0 findings, 0 errors).
