# waffle-taskView — notes

Audited and refactored the Waffle Task View overview module (`modules/waffle/taskView/`), covering `WaffleTaskView.qml`, `TaskViewContent.qml`, `TaskViewWindow.qml`, `TaskViewWorkspace.qml`, and `window-layout.js`.

## Findings

1. **Missing Bound Component Behavior:**
   Only `WaffleTaskView.qml` had `pragma ComponentBehavior: Bound`. Added the bound pragma to `TaskViewContent.qml`, `TaskViewWindow.qml`, and `TaskViewWorkspace.qml`.

2. **Premature Window Unload & Broken Exit Animation:**
   - Previously, closing the task view was prone to race conditions where `panelLoader.active = false` destroyed the window before the exit animation could play or desynchronized if toggled again mid-exit.
   - Introduced `shouldBeActive` latching in `WaffleTaskView.qml`.
   - Added symmetric `open()` and `close()` functions to `TaskViewContent.qml` that stop the opposing animation and transition smoothly from the current `openProgress`.
   - Connected `onClosed` to reset `panelLoader.shouldBeActive = false` only when the closing animation completes.

3. **Window Preview Snapping on Exit:**
   - `TaskViewContent` previously had `scaleSize: (root.openProgress > 0 && !closeAnim.running)`, causing `scaleSize` to flip to `false` on the first frame of close.
   - This snapped thumbnail dimensions up to full monitor resolution (`1920x1080`) while `closeAnim` was playing, blowing out the grid layout.
   - Fixed by keeping scaled thumbnail sizes stable during the entire enter/exit lifecycle.

4. **Broken Drag & Drop Handling (`drag.active` vs `root.Drag.active`):**
   - `TaskViewWindow.qml` checked `drag.active` (the MouseArea's inactive property) rather than `root.Drag.active` (the attached Qt Quick Drag property populated by `DragHandler`).
   - Consequently, dragging styles (translucency, border hide, titlebar fade, droppable preview scale) were never triggered.
   - Fixed by referencing `root.Drag.active` everywhere.
   - In `TaskViewContent.qml`, ensured `openedX` and `openedY` are always reset to 0 upon drag release, and added null guards for client address and target workspace.

5. **Division by Zero & NaN Coordinates in Workspace Previews:**
   - In `TaskViewWorkspace.qml`, `screenWidth / screenHeight` and `wallpaperHeight / screenHeight` evaluated before parent window dimensions were resolved, causing `0 / 0 = NaN` and `124 / 0 = Infinity`.
   - Every window thumbnail in workspace previews inherited `x: Infinity, y: Infinity`.
   - Resolved by fallback sizing (`1920x1080`) and guarding with `screenHeight > 0`.

6. **Missing Screen Lock Occlusion & Compositor Focus Grab:**
   - Added `GlobalStates.screenLocked` checks to IPC handlers, global shortcut, and loader. If the screen locks while task view is open, it dismisses immediately.
   - Added `HyprlandFocusGrab` on the focused monitor to dismiss the overview if compositor focus is cleared.
   - Set dynamic `WlrLayershell.keyboardFocus: (GlobalStates.overviewOpen && !GlobalStates.screenLocked) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None` so underlying windows regain keyboard input immediately upon dismiss.

7. **GPU Screencopy Frame Leakage:**
   - `ScreencopyView.live` was set to `true` unconditionally across all window cards and workspace cards, capturing GPU framebuffers even when task view was idle or closed.
   - Bound `live: GlobalStates.overviewOpen` across `TaskViewWindow.qml` and `TaskViewWorkspace.qml`.

8. **Crash on Null / Undefined Hyprland Data:**
   - Added null guards in `window-layout.js` (`scaleWindow`) to handle missing or 0-size clients.
   - Added null guards in `workspaceIndexModel.count` (`HyprlandData.workspaces`) and `workspaceListView.reposition()`.

9. **Design System & 4dp Grid Violations:**
   - Replaced literal animation durations (`250ms`, `200ms`, `300ms`) and `Easing.OutExpo` with `Appearance.animation.elementMoveEnter`, `Appearance.animation.elementMoveExit`, and `Appearance.animation.elementMoveFast`.
   - Aligned `spacing: 25` -> `24dp`.
   - Aligned `workspaceListView` margins (`5dp` -> `4dp`).
   - Aligned `topMargin: 9` -> `8dp` in `TaskViewWorkspace.qml`.
   - Aligned `CloseButton` from `38x38` to standard `32x32dp`.
   - Aligned active desktop indicator pill from `implicitHeight: 3` to `4dp` (`radius: 2`).
   - Aligned minimum window card width to `140dp`.

10. **Dead Code Cleanup:**
    - Removed unused `searchingText` and `dontAutoCancelSearch` scaffolding.
    - Removed redundant nested `wsBg` Rectangle in `TaskViewContent.qml`.

## Verification

- **Automated Regression Gate (`tools/check-waffle-taskview.py`):**
  Asserts `pragma ComponentBehavior: Bound` across all files, lifecycle latching (`shouldBeActive`), stoppable `open()`/`close()`, screen lock and focus grab, `root.Drag.active` correctness, NaN/zero-division guards, ScreencopyView live gating, and 4dp grid compliance. Exits 0.
- **Design Check (`tools/check-design.py --diff`):**
  Passes with 0 findings, 0 errors. Full `-v` check also clean for `taskView`.
