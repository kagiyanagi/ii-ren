# waffle-onScreenDisplay — brief

**Purpose.** The transient on-screen display (OSD) overlay for volume and brightness feedback in the Waffle panel family (Windows 11 Fluent style). Anchors to the bottom or top center adjacent to the Waffle taskbar, slides into view on volume/brightness hardware events or IPC triggers, displays icon, progress bar, and level percentage, and smoothly dismisses after a configurable timeout or on key press/screen lock.

**Primary action.** Passive feedback for hardware volume/brightness keys; IPC callable via `ipc call osd trigger [indicator]`, `ipc call osdVolume trigger`, and toggle/hide/open commands.

**Hierarchy.**
1. **Scope (`WaffleOSD.qml`)**: Listens to hardware events (`Audio.sink?.audio`, `Brightness`), IPC calls (`IpcHandler` for `osd` and `osdVolume`), and global shortcuts.
2. **Loader (`panelLoader`)**: Lazy window lifecycle. Unloaded (inactive) when idle, saving compositor surface allocation and GPU texture overhead.
3. **PanelWindow (`panelWindow`)**: Anchored bottom/top center on `WlrLayer.Overlay`, `screen: root.focusedScreen`, masked with `Region { item: osdIndicatorLoader }`.
4. **Loader (`osdIndicatorLoader`)**: Loads `VolumeOSD.qml` or `BrightnessOSD.qml`.
5. **OSDValue (`WBarAttachedPanelContent`)**: Slide enter/exit animation, auto-close timer (`Config.options.osd.timeout`), `WPane` rounded card on 4dp grid, `FluentIcon`, `WProgressBar`, `WTextWithFixedWidth`.

**Reference.** Windows 11 Fluent flyouts combined with ii-ren design tokens and Fluent styling (`modules/waffle/looks/Looks.qml`).

**What is wrong, measured.**
- **Crash on IPC / GlobalShortcut (`root.trigger()` does not exist).** `IpcHandler` and `GlobalShortcut` called `root.trigger()`, which was nowhere defined on `root`, throwing `TypeError` whenever `ipc call osd trigger` or the shortcut was invoked.
- **Crash on Monitor Switch (`ReferenceError: osdRoot is not defined`).** `WaffleOSD.qml` listened on `focusedScreenChanged` to run `osdRoot.screen = root.focusedScreen`, but `osdRoot` was undefined (`panelWindow` was the ID). Fixed by removing the broken imperative handler and binding `screen: root.focusedScreen` declaratively on `PanelWindow`.
- **Missing Bound Component Behavior.** Missing `pragma ComponentBehavior: Bound` across all 4 files (`WaffleOSD.qml`, `OSDValue.qml`, `VolumeOSD.qml`, `BrightnessOSD.qml`).
- **Broken Indicator Switching Transition (`Behavior on source`).** `Behavior on source` on `osdIndicatorLoader` evaluated `osdIndicatorLoader.item.closeAnimDuration` on startup when `item` was null (throwing TypeError) and called `item.close()` whose completion emitted `closed` signal, causing `panelLoader.active = false` to destroy the window before the next indicator could load.
- **Off-Grid Metrics in `OSDValue.qml`.** `implicitHeight: 46` violated the 4dp grid (fixed to 48dp), `implicitWidth: 170` (fixed to 168dp), `Layout.rightMargin: 3` (fixed to 4dp), and `FluentIcon` `implicitSize: 18` (fixed to 16dp).
- **Hardcoded Width Overriding Font Metrics in `WTextWithFixedWidth`.** Hardcoded `implicitWidth: 16` and commented-out `longestText: "100"` caused values like "100" to clip or elide. Restored `longestText: "100"` and removed clipping override.
- **Missing Fullscreen Occlusion Hiding.** Ignored `Config.options.osd.hideWhenFullscreen`. Added workspace-aware `hasFullscreenWindow` detection to prevent OSD popups over fullscreen games and videos.
- **Missing Indicator Enablement Gating.** Failed to check `Config.osdIndicatorEnabled(indicator)` and `Config.options.osd.enable`.
- **Screen Lock Occlusion & Spurious Startup Trigger.** OSD lacked screen lock guards (could display over lock screen) and startup timer gating (hardware probe events on boot triggered unwanted popups).

**Interaction.**
- Volume or brightness adjustment slides the OSD card smoothly up from the taskbar edge.
- If already visible, subsequent adjustments restart the dismiss timer and update progress immediately without sliding out.
- Switching between volume and brightness updates content cleanly in place.
- Auto-closes after `Config.options.osd.timeout` (default 3000ms) with a 150ms slide exit animation.
- Dismisses immediately on screen lock or Escape.

**Edge states.**
- Fullscreen window active on monitor: OSD suppressed if `Config.options.osd.hideWhenFullscreen` is true.
- Screen locked: OSD immediately closed and suppressed.
- Audio sink not ready or disconnected: null-guarded gracefully without exceptions.
- Disconnected or unmanaged monitor brightness: falls back safely to target monitor without exceptions.
- Shell boot: initial 1000ms startup timer prevents false triggers during device discovery.

**Cost.**
- Saves layer-shell surface allocations by keeping `panelLoader` inactive when idle.
- Eliminates QML type errors and broken connections on monitor focus change.

**Delete.**
- Removed 5 dead imports in `OSDValue.qml` (`Controls`, `Quickshell`, `qs`, `qs.services`, `common.functions`).
- Removed broken `Behavior on source` anti-pattern.
- Removed broken `osdRoot` imperatively wired connection.

**Out of scope.**
- Modifying underlying Pipewire or brightnessctl backend services.
