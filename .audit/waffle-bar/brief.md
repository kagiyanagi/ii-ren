# waffle-bar — brief

**Purpose.** The persistent shell taskbar and status panel for the Waffle family (Windows 11 Fluent style). Houses pinned and running applications with live window previews, the Start menu button, search trigger, Task View trigger, system status cluster (network, volume, battery), notifications & clock, package updates notifier, and the system tray. Anchors to either the bottom (default) or top screen edge.

**Primary action.** Launching, switching, and previewing active application windows; accessing the Start menu and quick status centers (Action Center and Notification Center).

**Hierarchy.**
1. **Left / Bloat Row**: Widgets button (when center-aligned) or start group anchor.
2. **Center / Apps Row**: Start menu button, Search button, Task View button, and running/pinned taskbar apps (`Tasks` list). Moves to left edge when `Config.options.waffles.bar.leftAlignApps` is enabled.
3. **Right / System Row**: System tray with expandable overflow flyout, package update alert button, system status cluster button (Wi-Fi, volume, battery), and clock/calendar button. Contains the Widgets button when `leftAlignApps` is enabled.
4. **Flyouts / Overlays**:
   - `TaskPreview`: Multi-window thumbnail card previews on task button hover with live ScreencopyView and close buttons.
   - `BarMenu`: Right-click context menus for app actions, unpin/pin, close, and system utilities.
   - `TrayOverflowMenu`: Expandable grid of unpinned system tray icons with drag-and-drop re-pinning.

**Reference.** Windows 11 taskbar adapted to ii-ren design tokens, Looks Fluent style system, and Wayland compositor layer shell (`.github/DESIGN.md`).

**What is wrong, measured.**
- **Missing screen lock gating and persistent focus grab.** `WaffleBar.qml` kept the bar active and interactive even when the lock screen was visible (`GlobalStates.screenLocked`), and did not register itself with `GlobalFocusGrab.addPersistent(barRoot)` / `removePersistent(barRoot)`.
- **Screen list filtering ignored.** `WaffleBar.qml` directly iterated `Quickshell.screens` instead of respecting `Config.options.bar.screenList` when configured.
- **FadeLoader passing instantiated item instead of Component.** In `WaffleBarContent.qml`, `FadeLoader` passed `sourceComponent: WidgetsButton {}`. Passing an instantiated item instead of `Component { WidgetsButton {} }` causes premature instantiation and runtime warnings.
- **MouseArea left-click hijacking in BarButton.** `BarButton.qml` wrapped an unnecessary child `MouseArea` capturing `Qt.LeftButton`, overriding `WButton`'s native Qt Quick Controls click and hover handling, causing erratic hover states and stuck `down = true` states on pointer drag-off.
- **Detached quickshell IPC subprocess call in StartButton.** `StartButton.qml` executed `Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "overview", "toggle"])` to toggle overview/search instead of updating `GlobalStates.searchOpen` in-process.
- **Unsafe Audio.sink access in SystemButton.** Volume and mute bindings lacked null safety on `.audio` (`Audio.sink?.audio.muted` and `Audio.sink?.audio.volume`), causing TypeErrors on startup if Pipewire sinks were still initializing. Disconnected network status also lacked fallback text.
- **Unsafe desktopEntry and toplevel calls in TaskAppButton.** Fallback execution and middle-click actions called `root.desktopEntry.execute()` without null-checking. Closing windows in context menu did not null-check `toplevel?.close?.()`.
- **Abrupt closing and expensive GPU offscreen pass in TaskPreview.** Window preview popup vanished abruptly on `close()` with no exit animation. `TaskPreview.qml` also used `layer.enabled: true` and `layer.effect: OpacityMask` on `contentItem`, adding unnecessary offscreen render passes.
- **Division by zero / NaN in TrayOverflowMenu.** `GridLayout` calculated `rows: Math.floor(Math.sqrt(TrayService.unpinnedItems.length))` and `columns: Math.ceil(...)`, producing `rows: 0` and `columns: NaN` when no unpinned items were present.
- **Off-grid design metrics and hardcoded literal durations.**
  - `AppButton.qml`: Stacked cards offset `rightMargin: 3` and `5` (off-grid; corrected to 4).
  - `TimeButton.qml`: `spacing: 7` -> 8, `rightPadding: 22` -> 20.
  - `UpdatesButton.qml`: `margins: 1` -> 2.
  - `tasks/TaskAppButton.qml`: `bottomMargin: 1` -> 2.
  - `tasks/WindowPreview.qml`: `padding: 5` -> 4, `spacing: 5` -> 4, close button `30` -> 28.
  - `BarPopup.qml` and `AppButton.qml`: Hardcoded durations without motion annotations.
- **Missing Bound ComponentBehavior.** 18 of 22 QML files in `modules/waffle/bar` lacked `pragma ComponentBehavior: Bound`.

**Interaction.**
- Primary launcher/switcher clicks focus active toplevels or launch apps. Middle-clicking launches a new instance.
- Right-clicking tasks or buttons opens context menus (`BarMenu`).
- Hovering a running app reveals `TaskPreview` thumbnails after a short delay (200ms enter animation, 150ms exit animation).
- Dragging tray items out of the overflow menu unpins them to the bar; dragging pinned items back re-pins them.

**Edge states.**
- Screen locked: Bar disables completely (`!GlobalStates.screenLocked`).
- Multi-screen setup: Bar honors `Config.options.bar.screenList` if configured.
- Zero unpinned tray items: Overflow grid safely clamps rows and columns to at least 1 without NaN errors.
- Pipewire sinks or network uninitialized: Safe fallbacks prevent crashes and unhandled TypeErrors.

**Cost.**
- Eliminates offscreen layer rendering in `TaskPreview`.
- Removes detached quickshell IPC processes.
- Eliminates stuck button press states and unhandled TypeErrors.

**Delete.**
- Redundant child `MouseArea` in `BarButton.qml`.
- Redundant `default property var menuData` in `BarMenu.qml`.
- Imperative `onDownChanged` animation logic in `AppButton.qml` and `WidgetsButton.qml`.
- Offscreen `OpacityMask` layer pass in `TaskPreview.qml`.

**Out of scope.**
- Modifying underlying Pipewire or Hyprland IPC daemon services.
