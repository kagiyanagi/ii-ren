# waffle-notificationCenter — brief

**Purpose.** The notifications hub and calendar/timer flyout for the Waffle panel family (Windows 11 Fluent style). Houses grouped application notifications with inline action buttons, mute toggle, Clear All, full interactive month/year calendar widget with collapse toggle, and Pomodoro focus session footer. Attached to the right screen edge.

**Primary action.** Reviewing and dismissing notifications, executing inline notification actions, checking calendar dates, and starting Pomodoro focus sessions.

**Hierarchy.**
1. **Notification Area (Top Pane)**:
   - Header with "Notifications" title, silent mode (DND) toggle, and "Clear all" button.
   - Scrollable list of notifications grouped by application (`WNotificationGroup`).
   - Each group contains app icon, app name, group dismiss button, and stacked individual notifications (`WSingleNotification`) with expandable actions and image previews.
   - Collapses to a compact 230dp empty state ("No new notifications") when no notifications exist.
2. **Calendar Area (Bottom Pane)**:
   - Date header with collapse/expand chevron.
   - Month and year navigation header with smooth week-scrolling calendar view (`CalendarView`).
   - Focus session footer with Pomodoro duration increment/decrement controls and start/stop session toggle.

**Reference.** Windows 11 Notification Center & Calendar flyout adapted to ii-ren design tokens, Looks Fluent style system, and Wayland compositor layer shell (`.github/DESIGN.md`).

**What is wrong, measured.**
- **Premature unmapping / lost exit animation.** `WaffleNotificationCenter.qml` bound `panelLoader.active: GlobalStates.sidebarRightOpen` directly. Toggling off the panel immediately destroyed the surface on the same frame, completely skipping `WBarAttachedPanelContent`'s 150ms slide-out exit animation.
- **Missing screen lock gating and focus grab.** `WaffleNotificationCenter.qml` lacked gating against `GlobalStates.screenLocked`, remaining visible when the session was locked, and its `HyprlandFocusGrab` remained unconditionally active.
- **Detached quickshell IPC subprocess call.** `FocusFooter.qml` executed `Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "sidebarRight", "toggle"])` to close the panel on focus session start instead of toggling in-process `GlobalStates.sidebarRightOpen = false`.
- **Non-functional notification action buttons.** `WSingleNotification.qml` rendered action buttons (`WBorderedButton`) with labels, but omitted an `onClicked` handler entirely. Clicking any action button did nothing.
- **Broken dismiss animation & invalid PropertyAction.** `WNotificationDismissAnim.qml` attempted to set `"ListView.delayRemove"` as a string target in `PropertyAction`, which fails on Qt Quick attached properties. It also used a hardcoded literal `250` duration and discarded notifications before the slide animation played, causing items to snap out instantly.
- **Invisible interactive dismiss button.** `WSingleNotification.qml` set `opacity: (root.containsMouse || root.isPopup) ? 1 : 0` without setting `visible: opacity > 0`, leaving a transparent 16x16 button intercepting mouse clicks at the top-right corner of every card when not hovered.
- **Anti-pattern root anchors in contentItem.** `NotificationPaneContent.qml` declared `anchors.fill: parent` on its root while being the `contentItem` of `WPane`, fighting `WPane`'s implicit sizing. It also used `FooterRectangle` instead of standard `Item`.
- **Negative implicit height calculations.** `NotificationCenterContent.qml` computed `((contentLayout.height - calendarPane.height - contentLayout.spacing) - notificationPane.borderWidth * 2)`, which produced negative height during initial opening frames before layout geometry settled.
- **Unclamped Pomodoro focus duration.** `FocusFooter.qml` subtracted 300 seconds unconditionally on `-` click, allowing focus time to reach 0 or negative numbers.
- **Off-grid geometry violations across multiple files.**
  - `CalendarWidget.qml`: `buttonSize: 41` -> `40`, `buttonSpacing: 6` -> `4`, `buttonVerticalSpacing: 1` -> `2`, `topMargin: 10` -> `8`, `leftMargin: 5` -> `8`, `rightMargin: 5` -> `8`, `spacing: 1` -> `2`, header button `implicitHeight: 34` -> `32`.
  - `FocusFooter.qml`: `implicitWidth: 81` -> `80`.
  - `WSingleNotification.qml`: `spacing: 19` -> `16`, `spacing: 3` -> `4`, `horizontalPadding: 10` -> `12`, `implicitSize: 14` -> `16`, `implicitSize: 18` -> `16`.
  - `WNotificationGroup.qml`: `Layout.margins: 11` -> `12`, `Layout.leftMargin: -Math.min(35, ...)` -> `-Math.min(36, ...)`, `spacing: 7` -> `8`, `Layout.rightMargin: 3` -> `4`.
  - `SmallBorderedIconAndTextButton.qml`: `implicitSize: 14` -> `16`.
- **Missing Bound ComponentBehavior.** 7 of 13 QML files lacked `pragma ComponentBehavior: Bound`.

**Interaction.**
- Panel slides in from right screen edge (200ms `Looks.transition.enter`), slides out (150ms `Looks.transition.exit`).
- Escape key closes via `WBarAttachedPanelContent`.
- Clicking outside closes via `HyprlandFocusGrab.onCleared` triggering `content.close()`.
- Swiping or clicking dismiss on a notification slides it out to the right (`Appearance.animation.elementMoveExit.duration`) before discarding from `Notifications` service.
- Clicking an action button invokes `Notifications.attemptInvokeAction(...)`.

**Edge states.**
- Screen locked: Panel automatically closes and disables input grab.
- Zero notifications: Notification pane smoothly shrinks to 230dp placeholder ("No new notifications") above calendar.
- Pomodoro timer: Decrement clamped to 300s minimum (5 minutes).
- Initial opening frame: Clamped with `Math.max(230, ...)` preventing negative implicit height warnings.

**Cost.**
- Eliminates detached quickshell IPC subprocesses.
- Eliminates premature surface unmapping and visual tearing on close.
- Eliminates phantom clicks on invisible buttons.

**Delete.**
- Broken `PropertyAction` targeting `"ListView.delayRemove"`.
- Detached quickshell IPC subprocess invocation in `FocusFooter.qml`.
- Redundant `FooterRectangle` root in `NotificationPaneContent.qml`.

**Out of scope.**
- Modifying underlying Quickshell `Notifications` or `TimerService` daemon services.
