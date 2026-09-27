# waffle-notificationPopup — brief

**Purpose.** The ephemeral toast notification stack for the Waffle panel family (Windows 11 Fluent style). Manages overlay placement, lifetime latching, input mask region, and animated presentation for incoming application notifications at the screen corner.

**Primary action.** Viewing incoming notification toasts as they arrive, reading summaries and previews, taking inline actions, or dismissing toasts via click or swipe.

**Hierarchy.**
1. **PanelWindow (Layer Shell Overlay)**:
   - Full height overlay anchored to `top`, `bottom`, and `right` screen edges.
   - Transparent background with dynamic click-through mask bounded to the active notification stack.
   - Pinned monitor resolution with fallback to the focused monitor.
   - Explicit `WlrKeyboardFocus.None` to ensure notifications never steal keyboard focus from active user tasks.
2. **Notification Stack (`WListView`)**:
   - Anchored to bottom right above the taskbar when `Config.options.waffles.bar.bottom` is true (Windows 11 standard), or to top right when the bar is positioned at the top.
   - Standard 384dp width (360dp card width + 12dp horizontal padding on the 4dp grid), matching the width of the Waffle Notification Center flyout.
   - Smooth entrance fade transition on `Appearance.animation.elementMoveFast`.
   - Delegates rendered via `WSingleNotification { isPopup: true }` featuring expandable action buttons, swipe-to-dismiss drag gesture, and animated removal.

**Reference.** Windows 11 notification toast stack adapted to ii-ren design tokens, Looks Fluent styling, and Wayland layer shell conventions (`.github/DESIGN.md`).

**What is wrong, measured.**
- **Premature surface unmapping on dismissal.** `visible` was bound directly to `(Notifications.popupList.length > 0) && !GlobalStates.screenLocked`. When the last popup timed out, was dismissed, or was dismissed via `Notifications.timeoutAll()` upon opening the Notification Center, `popupList.length` immediately dropped to 0, destroying the layer surface on that exact frame. As a result, `WSingleNotification`'s 150ms `WNotificationDismissAnim` exit animation was cut short and never drawn.
- **Missing pragma ComponentBehavior: Bound.** `WaffleNotificationPopup.qml` lacked the bound component behavior pragma, violating modern QML practices and audit requirements.
- **Unspecified keyboard focus.** The surface did not explicitly declare `WlrLayershell.keyboardFocus: WlrKeyboardFocus.None`, allowing edge cases where incoming notification overlays could grab keyboard focus.
- **Ignored monitor configuration.** The screen binding only inspected `Hyprland.focusedMonitor?.name`, ignoring the user's pinned notification monitor setting (`Config.options.notifications.monitor`).
- **Contradictory width and anchor constraints.** `WListView` declared both `anchors.left: parent.left` and `anchors.right: parent.right` while simultaneously declaring `width: parent.width - Appearance.sizes.elevationMargin * 2`. In QML, specifying width on an item with opposing horizontal anchors produces runtime geometry conflicts and console warnings.
- **Off-grid metrics and mismatched panel width.** `WListView` declared `implicitWidth: 396` with `leftMargin: 16` and `rightMargin: 16`, yielding an off-standard 364dp card width. Waffle Notification Center uses 360dp card width. Standardizing on `implicitWidth: 384` with 12dp margins aligns the popup cards to exactly 360dp on the 4dp grid.
- **Mask region swallowing empty space.** `popupBounds` tracked `listview.height`, which computed `Math.min(contentItem.height + topMargin + bottomMargin, parent.height)`. When the popup list was empty, `listview.height` evaluated to `topMargin + bottomMargin` (32dp), causing an empty 32dp rectangle to swallow pointer clicks at the bottom right.
- **Unpublished notification popup height.** `GlobalStates.notificationPopupHeight` was never bound or published under Waffle. When notifications were displayed, top-right overlays (`ClipboardToast`, `FastPairPopup`, `ScreenshotPreviewPopup`) were unaware of the popups. When notifications are anchored to the top (`!barAtBottom`), the stack height must be published; when bottom-anchored, 0 must be published so top-right readers do not inset needlessly.

**Interaction.**
- Incoming notifications arrive with a smooth fade-in (`elementMoveFast`).
- Individual notifications can be dismissed via the close button or dragged horizontally past the 100dp drag dismiss threshold.
- Dismissing an item runs `WNotificationDismissAnim`, which smoothly slides the card out to the right over `Appearance.animation.elementMoveExit.duration`.
- When the last notification leaves the model, the `mapped` latch keeps the window mapped for the full duration of `exitGrace` (`Appearance.animation.elementMoveExit.duration`), allowing the exit animation to finish completely before unmapping.
- Clicking outside has no effect because `exclusiveZone: 0` and `popupBounds` mask only the active notification stack; all slack is completely click-through.

**Edge states.**
- Screen lock: Surface immediately hides via `!GlobalStates.screenLocked`.
- Empty popup list: `popupBounds.height` reports 0 and `notificationPopupHeight` publishes 0, ensuring zero pointer obstruction.
- Notification Center opened: Opening the right sidebar triggers `Notifications.timeoutAll()`, smoothly animating toasts out over the exit grace period without graphical pops.
- Taskbar at top: When `Config.options.waffles.bar.bottom` is false, toasts anchor to the top right and publish their stack height to `GlobalStates.notificationPopupHeight`.
