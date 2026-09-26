# waffle-actionCenter — notes

**Opening it.**
- Active under `Config.options.panelFamily: "waffle"` (or cycling via `qs -c ii ipc call panelFamily cycle`).
- Toggled via `qs -c ii ipc call sidebarLeft toggle` or the `sidebarLeftToggle` shortcut (`Super+A` by default in Waffle).
- Subpages (Wi-Fi, Bluetooth, Sound, Eye protection) open via the chevron on the corresponding split quick toggle or the options button next to the volume slider.

**Measured and fixed.**
- **Invisible media pane dead space:** In `ActionCenterContent.qml`, `WPane` containing `MediaPaneContent` had `opacity: (hasMedia) ? 1 : 0` without setting `visible: hasMedia`. Because `ColumnLayout` only collapses invisible items, when no media player was active the panel allocated a 176px tall empty dead zone at the top. Setting `visible: hasMedia` ensures the layout dynamically collapses to only show the toggles and footer.
- **Rogue Bluetooth discovery on eye protection:** In `nightLight/NightLightControl.qml`, lines 18–24 contained copy-pasted `Bluetooth.defaultAdapter.discovering = true/false` logic along with an unused `Quickshell.Bluetooth` import. Opening the eye protection menu unintentionally turned on Bluetooth scanning and threw runtime null-reference errors on systems without an active adapter. All Bluetooth code and imports were excised.
- **Undefined `contentLayout` ReferenceErrors:** `wifi/WifiControl.qml` and `bluetooth/BluetoothControl.qml` both declared `contentHeight: contentLayout.implicitHeight` on their `StyledListView`s, but neither defined `contentLayout`. In QtQuick, `ListView` calculates its own scrollable content geometry; this threw `ReferenceError: contentLayout is not defined`. Removed the redundant assignments.
- **Detached IPC subprocess execution to close self:** In `WifiControl.qml`, `BluetoothControl.qml`, and `VolumeControl.qml`, clicking the external settings button ran `Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "sidebarLeft", "toggle"])` to close the panel before launching the app. This was slow and spawned an extra process; replaced with immediate in-process `GlobalStates.sidebarLeftOpen = false`.
- **EasyEffects gating on volume mixer header:** In `volumeControl/VolumeControl.qml`, the `SectionText` for "Volume mixer" was erroneously set to `visible: EasyEffects.available`. On systems without EasyEffects, the header vanished while the per-application volume sliders below remained rendered. Removed the gate so the header is always visible above app audio streams.
- **Custom text button replaced with WTextButton:** In `volumeControl/VolumeControl.qml`, the footer had a hand-rolled `WButton` with `color: "transparent"` and arbitrary width padding. Replaced with `WTextButton` matching Wi-Fi and Bluetooth controls.
- **Audio sink/source null safety:** In `mainPage/MainPageBodySliders.qml` and `volumeControl/VolumeEntry.qml`, volume bindings now use optional chaining (`Audio.sink?.audio?.volume ?? 0`) and check node/audio existence before setting volume or toggling mute, eliminating TypeErrors on early startup before Pipewire initializes sinks.
- **StackView state reset on close:** In `ActionCenterContext.qml` and `ActionCenterContent.qml`, added `ActionCenterContext.reset()` on panel close so reopening the flyout returns to the primary quick-settings grid rather than persisting inside a previously browsed subpage. Also wired `Escape` key handling to navigate back (`back()`) if nested in a subpage before closing the panel.
- **Clickable dummy button replaced:** In `mainPage/MainPageBodySliders.qml`, an invisible `WPanelIconButton { opacity: 0 }` was used to pad the right side of the brightness slider. It intercepted pointer clicks and cursor changes. Replaced with an inert `Item { implicitWidth: 40; implicitHeight: 40 }` spacer.
- **Grid alignment and token cleanliness:** Corrected off-4dp-grid numbers flagged by `tools/check-design.py`:
  - `MediaPaneContent.qml`: `leftMargin: 23` -> 24, `rightMargin: 23` -> 24, `spacing: 25` -> 24, `spacing: 26` -> 24, `Layout.preferredWidth: 58` -> 56.
  - `ToggleItem.qml`: `spacing: 1` -> 2.
  - `mainPage/MainPageBody.qml`: `topMargin: 18` -> 16, `bottomMargin: 14` -> 12, replaced raw `Rectangle` separator with `WPanelSeparator`.
  - `mainPage/MainPageBodyToggles.qml`: `padding: 22` -> 20.
  - `wifi/WWifiNetworkItem.qml`: `spacing: 1` -> 2, `Layout.topMargin: 7` -> 8.
- **Modern QML Bound ComponentBehavior:** Added `pragma ComponentBehavior: Bound` across all 21 QML files under `modules/waffle/actionCenter/`.

**Automated verification.**
- Added `tools/check-waffle-actioncenter.py` validating Bluetooth isolation in NightLightControl, absence of `contentLayout` references, lack of detached self-IPC subprocess calls, volume mixer header gating, audio null safety, collapsing media pane, and 4dp grid metrics.
