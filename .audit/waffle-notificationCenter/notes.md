# waffle-notificationCenter — notes

**Opening it.**
- Active under `Config.options.panelFamily: "waffle"` (or cycling via `qs -c ii ipc call panelFamily cycle`).
- Toggled via `qs -c ii ipc call sidebarRight toggle` or the `sidebarRightToggle` global shortcut, or by clicking the clock/date button on the waffle taskbar (`TimeButton.qml`).

**Measured and fixed.**
- **Preserved exit animation and decoupled Loader lifetime:** In `WaffleNotificationCenter.qml`, removed the binding `panelLoader.active: GlobalStates.sidebarRightOpen`. Previously, when `sidebarRightOpen` flipped false, `panelLoader` instantly destroyed `panelWindow` and `NotificationCenterContent` on the same frame, killing the 150ms slide exit animation. Now `panelLoader.active` is set to `true` on open, and when `sidebarRightOpen` flips false, `content.close()` runs the exit animation, only setting `panelLoader.active = false` once `content.onClosed` fires.
- **Screen lock protection:** Added gating on `!GlobalStates.screenLocked` for `HyprlandFocusGrab` and closed the panel when the screen locks.
- **IPC handler parity:** Added `open()` and `close()` functions alongside `toggle()`, matching other waffle and ii surfaces.
- **Detached IPC subprocess execution:** In `FocusFooter.qml`, replaced `Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "sidebarRight", "toggle"])` with direct in-process state toggle `GlobalStates.sidebarRightOpen = false`.
- **Pomodoro focus timer safety:** In `FocusFooter.qml`, clamped focus decrement with `Math.max(300, ...)` so focus time cannot drop to 0 or negative numbers. Fixed `implicitWidth: 80` (was 81).
- **Interactive notification action buttons:** In `WSingleNotification.qml`, wired `onClicked: Notifications.attemptInvokeAction(root.notification?.notificationId, actionButton.modelData.identifier)` onto `WBorderedButton` action buttons. Previously, action buttons had no click handlers and did nothing.
- **Dismiss animation and delayRemove:** In `WNotificationDismissAnim.qml`, deleted invalid `PropertyAction` targeting string `"ListView.delayRemove"`, replaced hardcoded `250` duration with `Appearance.animation.elementMoveExit.duration`, and emitted a `dismissed` signal. Attached `ListView.delayRemove: removeAnimation.running` directly to `WNotificationGroup` and `WSingleNotification`, so notifications smoothly slide off-screen before being discarded from the `Notifications` service.
- **Disabled drag Behavior while active:** Prevented `Behavior on x` from fighting pointer drag events and explicit dismiss animations by gating with `enabled: !root.drag.active && !removeAnimation.running`.
- **Invisible interactive button fix:** In `WSingleNotification.qml`, added `visible: opacity > 0` to `NotificationHeaderButton` so the transparent dismiss button does not intercept clicks when not hovered.
- **ContentItem layout cleanliness:** In `NotificationPaneContent.qml`, replaced `FooterRectangle` root with `Item`, removed invalid `anchors.fill: parent` on `root`, and added null-safety on `Notifications.groupsByAppName?.[modelData]` and `Notifications.list`.
- **Opening height clamping:** In `NotificationCenterContent.qml`, clamped `implicitHeight` with `Math.max(230, ...)` to eliminate negative implicit height warnings during initial layout passes.
- **4dp spacing and metrics grid:**
  - `CalendarWidget.qml`: `buttonSize: 41` -> `40`, `buttonSpacing: 6` -> `4`, `buttonVerticalSpacing: 1` -> `2`, `topMargin: 10` -> `8`, `leftMargin: 5` -> `8`, `rightMargin: 5` -> `8`, `spacing: 1` -> `2`, header buttons `implicitHeight: 34` -> `32`.
  - `FocusFooter.qml`: `implicitWidth: 81` -> `80`.
  - `WSingleNotification.qml`: `spacing: 19` -> `16`, `spacing: 3` -> `4`, `horizontalPadding: 10` -> `12`, `implicitSize: 14` -> `16`, `implicitSize: 18` -> `16`.
  - `WNotificationGroup.qml`: `Layout.margins: 11` -> `12`, `Layout.leftMargin: -Math.min(35, ...)` -> `-Math.min(36, ...)`, `spacing: 7` -> `8`, `Layout.rightMargin: 3` -> `4`.
  - `SmallBorderedIconAndTextButton.qml`: `implicitSize: 14` -> `16`.
- **Modern QML Bound ComponentBehavior:** Added `pragma ComponentBehavior: Bound` across all 13 QML files in `modules/waffle/notificationCenter`.

**Automated verification.**
- Created `tools/check-waffle-notificationcenter.py` covering pragma declarations, lifetime management/exit animation, in-process IPC, Pomodoro clamp, 4dp grid metrics across all files, notification action invocation, dismiss animation/delayRemove, and null-safety.
- Ran `python3 tools/check-waffle-notificationcenter.py` (all tests passing).
- Ran `python3 tools/check-design.py --diff` (0 findings, 0 errors).
