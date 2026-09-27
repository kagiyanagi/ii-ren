# waffle-bar — notes

**Opening it.**
- Active under `Config.options.panelFamily: "waffle"` (or cycling via `qs -c ii ipc call panelFamily cycle`).
- Bar anchors to the bottom (default) or top screen edge (`Config.options.waffles.bar.bottom`).
- Toggled via `qs -c ii ipc call bar toggle` or the `barToggle` global shortcut.

**Measured and fixed.**
- **Screen lock protection and focus persistence:** In `WaffleBar.qml`, gated `barLoader.active` on `!GlobalStates.screenLocked` so the bar is disabled when the lockscreen is presented. Registered each screen's `PanelWindow` with `GlobalFocusGrab.addPersistent(barRoot)` / `removePersistent(barRoot)`. Added multi-screen filtering respecting `Config.options.bar.screenList`.
- **FadeLoader component encapsulation:** In `WaffleBarContent.qml`, `FadeLoader` passed raw `WidgetsButton {}` to `sourceComponent`. Replaced with `Component { WidgetsButton {} }` so the item is properly instantiated on demand rather than immediately.
- **Button input hijacking and stuck states:** In `BarButton.qml`, removed the redundant child `MouseArea` capturing `Qt.LeftButton`. Because `AcrylicButton` inherits `WButton` (which inherits Qt Quick Controls `Button`), the extra `MouseArea` caused hover glitches and left `root.down = true` when dragging off the button. `WButton` already handles secondary mouse buttons and signals natively.
- **Detached IPC subprocess execution:** In `StartButton.qml`, replaced `Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "overview", "toggle"])` with direct state update `GlobalStates.searchOpen = !GlobalStates.searchOpen`.
- **Audio sink and network null safety:** In `SystemButton.qml`, guarded `Audio.sink?.audio?.muted` and `Audio.sink?.audio?.volume`, and added `"Disconnected"` fallback for `Network.networkName`. Renamed confusing `id: column` to `id: systemButtonsRow`.
- **TaskAppButton safety and context menu guards:** In `tasks/TaskAppButton.qml`, guarded `root.desktopEntry?.execute()`, `root.appEntry?.toplevels`, and `toplevel?.close?.()`.
- **Window preview thumbnail smoothness and offscreen pass removal:** In `tasks/TaskPreview.qml`, implemented animated exit transition (`closeAnim`) mirroring `openAnim`. Removed unnecessary `layer.enabled: true` and `layer.effect: OpacityMask` on `contentItem`, relying on standard clipping and rounded backgrounds without offscreen GPU overhead.
- **Tray overflow menu zero/NaN crash guard:** In `tray/TrayOverflowMenu.qml`, clamped `rows` and `columns` using `Math.max(1, ...)` to guard against division by zero and `NaN` when `unpinnedItems` is empty.
- **4dp spacing grid and design alignment:**
  - `AppButton.qml`: `rightMargin: 3` and `5` -> 4.
  - `TimeButton.qml`: `spacing: 7` -> 8, `rightPadding: 22` -> 20.
  - `UpdatesButton.qml`: `margins: 1` -> 2.
  - `tasks/TaskAppButton.qml`: `bottomMargin: 1` -> 2.
  - `tasks/WindowPreview.qml`: `padding: 5` -> 4, `spacing: 5` -> 4, close button `implicitHeight: 30` -> 28, `implicitWidth: 30` -> 28.
  - `tasks/TaskPreview.qml`: `implicitHeight: Math.min(158, ...)` -> 160.
  - `WidgetsButton.qml`: `spacing: 6` -> 8.
- **Declarative press micro-interactions:** Replaced imperative `onDownChanged` duration/bezier reassignments in `AppButton.qml` and `WidgetsButton.qml` with declarative `scale` behaviors and tokenized easing curves.
- **Modern QML Bound ComponentBehavior:** Added `pragma ComponentBehavior: Bound` across all 22 QML files in `modules/waffle/bar/`.

**Automated verification.**
- Created `tools/check-waffle-bar.py` covering pragma bound declarations, IPC elimination, screenLock / focus grab, Component encapsulation in FadeLoader, MouseArea elimination in BarButton, null safety in audio/network/tasks, offscreen layer removal, zero-safe tray grid, and design checks.
- Ran `python3 tools/check-waffle-bar.py` (all tests passing).
- Ran `python3 tools/check-design.py --diff` (0 findings, 0 errors).
