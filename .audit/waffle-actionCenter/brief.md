# waffle-actionCenter — brief

**Purpose.** The quick-settings and notifications hub for the Waffle panel family (Windows 11 Fluent style). Provides instantaneous access to core system toggles (Wi-Fi, Bluetooth, Night Light, Dark Mode, etc.), media transport controls (MPRIS), display brightness, master audio sink volume, battery percentage, and settings shortcuts. Attached to the waffle bar at screen edge.

**Primary action.** Flipping a quick toggle (e.g. Wi-Fi on/off) or adjusting audio/brightness sliders. Secondary: opening detail subpages (chevron on split toggles: Wi-Fi network picker, Bluetooth device manager, sound output/mixer, eye protection).

**Hierarchy.**
1. **Media Pane** (top card, visible only when a player is active): Album art, track info, transport controls.
2. **Quick Toggles & Sliders** (main body card): Paginated 3x2 toggle grid with vertical page indicator, separator, brightness slider with animated sun icon, volume slider with mute toggle and mixer entry chevron.
3. **Footer**: Battery status pill with percentage, settings shortcut button.
4. **Subpages**: Replaces body/footer stack when drilled in (Header with back button, scrollable list of networks/devices/sliders, footer with external settings links).

**Reference.** Windows 11 Action Center flyout adapted to ii-ren design tokens and M3 Expressive integration (`.github/DESIGN.md`). Fluent styling adapted to the Waffle look system.

**What is wrong, measured.**
- **Invisible Media Pane takes up space.** `WPane` in `ActionCenterContent.qml` set `opacity: (MprisController.activePlayer != null && isRealPlayer(...)) ? 1 : 0` without setting `visible: opacity > 0`. Because `ColumnLayout` retains space for items with `visible: true` regardless of opacity, the action center rendered a ~178px empty blank box above the toggles when no music was playing.
- **Rogue Bluetooth discovery in Night Light subpage.** `NightLightControl.qml` copied over `Component.onCompleted: if (Bluetooth.defaultAdapter.enabled) Bluetooth.defaultAdapter.discovering = true;` and `Component.onDestruction: Bluetooth.defaultAdapter.discovering = false;`, and imported `Quickshell.Bluetooth`. Opening the eye protection subpage triggered Bluetooth discovery scans and threw runtime errors when no default adapter was available.
- **Unqualified / missing null-checks on Audio.** `MainPageBodySliders.qml` bound `value: Audio.sink.audio.volume` directly without null guards, throwing TypeError on shell startup if Pipewire had not yet initialized the default sink. Similarly, `VolumeEntry.qml` toggled `root.node.audio.muted` directly without checking if `audio` was null.
- **ReferenceError for non-existent `contentLayout`.** `WifiControl.qml` and `BluetoothControl.qml` specified `contentHeight: contentLayout.implicitHeight` in their `StyledListView`s, but neither file defines an `id: contentLayout`. ListView manages its own content dimensions; this threw `ReferenceError: contentLayout is not defined` whenever those subpages were navigated to.
- **Subprocess spawning to invoke IPC on self.** `WifiControl.qml`, `BluetoothControl.qml`, and `VolumeControl.qml` ran `Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "sidebarLeft", "toggle"])` to close the panel when launching full settings apps. Spawning a detached quickshell process to call IPC on oneself is slow and unreliable; directly setting `GlobalStates.sidebarLeftOpen = false` is instantaneous and clean.
- **Volume mixer header inappropriately gated on EasyEffects.** `VolumeControl.qml` had `SectionText { visible: EasyEffects.available; text: Translation.tr("Volume mixer") }`. When EasyEffects is not installed, the header vanished while the per-app volume sliders below remained visible.
- **Inconsistent and unstyled button in VolumeControl.** Re-implemented a raw `WButton` with hardcoded text and off-grid sizing instead of using `WTextButton` like `WifiControl` and `BluetoothControl`.
- **Subpage state retention across closes.** Closing the Action Center while in a subpage (e.g. Wi-Fi networks) left the `stackView` on that subpage. Reopening the panel showed the subpage instead of returning to the primary quick toggles. Escape key also did not pop subpages before closing.
- **Exit animation bypassed.** `WaffleActionCenter.qml` directly flipped `GlobalStates.sidebarLeftOpen` in `toggleOpen()` and shortcut handlers, immediately destroying `panelWindow.visible` before `content.close()` could execute the 150ms slide-out animation.
- **Invisible interactive dummy button in brightness slider.** `WPanelIconButton { opacity: 0 }` was used to reserve space on the right of the brightness slider, but still received mouse clicks and hovers.
- **Off-grid geometry violations.** 9 design-check violations across 5 files: `MediaPaneContent.qml` (margins 23->24, spacing 25->24, 26->24, art width 58->56), `ToggleItem.qml` (spacing 1->2), `mainPage/MainPageBody.qml` (topMargin 18->16, bottomMargin 14->12), `mainPage/MainPageBodyToggles.qml` (padding 22->20), `WWifiNetworkItem.qml` (spacing 1->2, topMargin 7->8).
- **Missing Bound ComponentBehavior & imports.** 15 files lacked `pragma ComponentBehavior: Bound`.

**Interaction.**
- Panel slides in from bottom/top edge (200ms `Looks.transition.enter`), slides out (150ms `Looks.transition.exit`).
- Escape pops subpage if `stackView.depth > 1`, otherwise slides out the panel.
- Subpages push with `WStackView` slide transitions; on panel close, `stackView.pop(null)` resets to root.
- Clicking outside closes via `HyprlandFocusGrab.onCleared` triggering `content.close()`.

**Edge states.**
- No active media player: `WPane` collapses completely (`visible: false`), panel shrinks to toggles + footer.
- Bluetooth or Wi-Fi scanning: indeterminate progress bar shown under header; rescan button disabled while scanning.
- Pipewire audio sink or source null: safe fallback to 0/empty, no TypeError.
- Battery not available (desktop PC): battery indicator in footer gracefully hides (`visible: Battery.available`).

**Cost.**
- Eliminates unneeded detached IPC processes and prevents unnecessary Bluetooth scans on eye protection.
- Eliminates 178px empty layout gap when no media player is active.

**Delete.**
- Remove rogue Bluetooth discovery code and import in `NightLightControl.qml`.
- Delete undefined `contentHeight: contentLayout.implicitHeight` references in `WifiControl.qml` and `BluetoothControl.qml`.
- Remove redundant property definitions in `WWifiNetworkItem.qml`.

**Out of scope.**
- Full redesign of the Waffle theme looks library or reimplementation of the network/bluetooth backends.
