# waffle-onScreenDisplay — notes

Audited and refactored the Waffle On-Screen Display module (`modules/waffle/onScreenDisplay/`), covering `WaffleOSD.qml`, `OSDValue.qml`, `VolumeOSD.qml`, and `BrightnessOSD.qml`.

## Findings

1. **Missing ComponentBehavior: Bound:**
   None of the 4 QML files declared `pragma ComponentBehavior: Bound`. Added the bound pragma across all 4 files.

2. **IPC Crash & Missing `root.trigger()` Definition:**
   `IpcHandler { target: "osd"; function trigger() { root.trigger(); } }` and `GlobalShortcut` called `root.trigger()`, which did not exist on `root`.
   - Implemented `function trigger(indicator)`, `function toggle(indicator)`, `function close()`, and `function closeImmediate()` on `root`.
   - Expanded `IpcHandler` for `osd` to support `trigger`, `open`, `hide`, `close`, and `toggle`.
   - Added backward-compatible `IpcHandler` for `osdVolume`.

3. **Monitor Switch ReferenceError (`osdRoot is not defined`):**
   `WaffleOSD.qml` contained:
   ```qml
   Connections {
       target: root
       function onFocusedScreenChanged() {
           osdRoot.screen = root.focusedScreen;
       }
   }
   ```
   `osdRoot` was undefined (`panelWindow` is the actual ID).
   Removed the imperative connection entirely and bound `screen: root.focusedScreen` directly on `PanelWindow`.

4. **Broken Indicator Switching Transition (`Behavior on source`):**
   `WaffleOSD.qml` attached a `Behavior on source` to `osdIndicatorLoader` with a `SequentialAnimation`:
   - It evaluated `osdIndicatorLoader.item.closeAnimDuration` at instantiation time when `item` was still null, throwing `TypeError`.
   - Calling `item.close()` fired the `closed` signal from `WBarAttachedPanelContent`, which triggered `panelLoader.active = false` and destroyed the window before the next indicator could load.
   - Removed the broken behavior so that switching indicators swaps the source cleanly and reactively without tearing down the window.

5. **Design System & 4dp Grid Violations in `OSDValue.qml`:**
   - `implicitHeight: 46` adjusted to `48` (divisible by 4).
   - `implicitWidth: root.showNumber ? 192 : 170` adjusted to `root.showNumber ? 192 : 168` (168 is divisible by 4).
   - `FluentIcon { implicitSize: 18 }` adjusted to `16` (divisible by 4).
   - `Layout.rightMargin: root.showNumber ? 0 : 3` adjusted to `root.showNumber ? 0 : 4` (divisible by 4).
   - Commented-out `longestText: "100"` was restored on `WTextWithFixedWidth`, and hardcoded `implicitWidth: 16` (which caused text clipping on "100") was removed.

6. **Fullscreen Occlusion & Indicator Enablement Gating:**
   - Implemented `hasFullscreenWindow` active workspace detection for Hyprland.
   - Gated all triggers on `Config.osdIndicatorEnabled(indicator)` and `Config.options.osd.hideWhenFullscreen`.
   - Prevented OSD display when `GlobalStates.screenLocked` is true, and added an immediate close hook on lock.

7. **Null Safety & Startup Delay:**
   - Added `isStartup: true` with a 1000ms delay to suppress spurious device discovery events when shell initializes.
   - Added null guards: `Audio.sink?.audio?.volume ?? 0` and `Brightness.getMonitorForScreen(focusedScreen) ?? Brightness.getTargetMonitor()`.

8. **Dead Imports Removed:**
   Cleaned up unused imports in `OSDValue.qml` (`QtQuick.Controls`, `Quickshell`, `qs`, `qs.services`, `qs.modules.common.functions`).

## Verification

- **Automated Regression Gate (`tools/check-waffle-onscreendisplay.py`):**
  Asserts `pragma ComponentBehavior: Bound` across all 4 files, no undefined references to `osdRoot`, `root.trigger()` availability, IPC handlers for `osd` and `osdVolume`, fullscreen and screenLocked gating, `Config.osdIndicatorEnabled` checking, 4dp grid metrics, `WTextWithFixedWidth` font metrics sizing, and null-safe property accesses. Passes with 0 errors.
- **Design Check (`tools/check-design.py --diff`):**
  Passed with 0 findings, 0 errors.
- **Mask Region Check (`tools/check-mask-regions.py`):**
  Passed with 0 errors.
