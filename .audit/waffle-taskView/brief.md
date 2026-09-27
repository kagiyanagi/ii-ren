# waffle-taskView — brief

**Purpose.** The multi-tasking and workspace overview module for the Waffle panel family (Windows 11 Fluent style). Presents an interactive bird's-eye view of open windows on the active workspace arranged in a balanced multi-row grid, alongside a sliding bottom workspace switcher strip showing all virtual desktops with miniature live window previews, desktop wallpaper previews, and a "New desktop" button. Supports window focusing, window closing, cross-desktop window pinning, dragging and dropping windows between workspaces, and keyboard navigation.

**Primary action.** Viewing and switching between open application windows and workspaces; organizing windows across virtual desktops via drag-and-drop; toggled via `Super+Tab`, `GlobalShortcut` (`overviewWorkspacesToggle`), or IPC (`ipc call taskView toggle`).

**Hierarchy.**
1. **Scope (`WaffleTaskView.qml`)**: Multi-screen variant manager. Listens to `GlobalStates.overviewOpen`, `GlobalStates.screenLocked`, IPC target `taskView`, and global shortcut `overviewWorkspacesToggle`.
2. **Loader (`panelLoader`)**: Per-screen lazy lifecycle manager. Decoupled via `shouldBeActive` state to latch surface lifecycle until the exit animation completes.
3. **PanelWindow (`root`)**: Fullscreen overlay on `WlrLayer.Overlay`, namespace `quickshell:wTaskView`. Coordinates `HyprlandFocusGrab` on focused monitor and dynamically yields keyboard focus to `WlrKeyboardFocus.None` during dismissal.
4. **TaskViewContent (`taskViewContent`)**:
   - Backdrop acrylic scrim fading smoothly with `openProgress`.
   - Click-to-dismiss `MouseArea` covering empty background.
   - Window list view (`WListView` / `windowListView`): Centered multi-row flow layout calculated by `WindowLayout.scaleWindow`.
   - Window cards (`TaskViewWindow`): Rounded window thumbnails with titlebar icon, window title, close button, live ScreencopyView thumbnail, and context menu. Supports interactive dragging with `DragHandler` and droppable scaling (shrinks to 0.4x scale when hovered over a target workspace).
   - Workspace switcher bar (`wsBorder` / `WListView` / `workspaceListView`): Sliding bottom panel containing `TaskViewWorkspace` cards for each desktop plus `New desktop`, with drop targets (`DropArea`) and active desktop indicator pill.
5. **Math (`window-layout.js`)**: Aspect-ratio scaling algorithm and client-packing math.

**Reference.** Windows 11 Task View combined with ii-ren Fluent tokens and motion curves (`.github/DESIGN.md`).

**What is wrong, measured.**
- **Missing Bound Component Behavior.** 3 out of 4 QML files (`TaskViewContent.qml`, `TaskViewWindow.qml`, `TaskViewWorkspace.qml`) omitted `pragma ComponentBehavior: Bound`.
- **Premature Window Unload & Broken Exit Animation.** The loader destroyed the window immediately on close without waiting for exit animation, or if closing was initiated, a subsequent toggle caused state desynchronization. Fixed with `shouldBeActive` latch and symmetrically stoppable `open()` / `close()` methods with `Appearance.animation.elementMoveEnter` and `Appearance.animation.elementMoveExit`.
- **Window Preview Thumbnail Snapping on Exit.** `TaskViewContent` set `scaleSize: (root.openProgress > 0 && !closeAnim.running)`, causing `scaleSize` to flip to `false` on the very first frame of closing, blowing up all window previews to full monitor resolution (1920x1080) and breaking the grid layout. Fixed by maintaining stable scaled thumbnail sizing throughout the lifecycle.
- **Broken Drag-and-Drop Handling (`drag.active` vs `root.Drag.active`).** `TaskViewWindow.qml` checked `drag.active` (MouseArea's inactive drag target) rather than the attached `root.Drag.active` property populated by `DragHandler`, leaving drag styling, border transparency, and titlebar fade completely broken. Furthermore, `openedX` and `openedY` were never reset on drop completion, and drag drop targets lacked null safety.
- **Zero Division / NaN Coordinates in Workspace Previews.** `TaskViewWorkspace.qml` computed `screenWidth / screenHeight` and `wallpaperHeight / screenHeight` before window geometry was resolved (when `screenHeight == 0`), producing `NaN` and `Infinity` which poisoned all preview coordinates. Guarded with fallback geometry and `screenHeight > 0`.
- **Crash on Empty/Null Workspace or Client Array.** `window-layout.js` and `workspaceIndexModel.count` evaluated `hyprlandClient.size` and `Math.max.apply(null, HyprlandData.workspaces.map(...))` without null guards, throwing unhandled TypeErrors or evaluating to `-Infinity`.
- **GPU Screencopy Leakage.** Screencopy views were set to `live: true` unconditionally across every window card and every workspace preview thumbnail even when closed. Bound `live: GlobalStates.overviewOpen`.
- **Missing Screen Lock Occlusion & Compositor Focus Handling.** Lacked `GlobalStates.screenLocked` checks and `HyprlandFocusGrab` dismissal handling.
- **Off-Grid Metrics and Motion Violations.**
  - 4 literal durations (`duration: 250`, `duration: 200`, `duration: 300`) and raw `Easing.OutExpo` curves.
  - Off-grid spacing `25` (fixed to 24dp), margins `5` (fixed to 4dp), `topMargin: 9` (fixed to 8dp), `implicitWidth: 138` (fixed to 140dp), `CloseButton` `38x38` (fixed to 32x32dp), and active indicator `implicitHeight: 3` (fixed to 4dp).

**Interaction.**
- Pressing `Super+Tab` or triggering IPC `taskView toggle` opens the overview: the backdrop dims, window cards animate from their mapped screen coordinates into a balanced grid, and the bottom workspace switcher slides up.
- Clicking any window card focuses the corresponding window via Hyprland and smoothly dismisses the overview.
- Right-clicking a window card opens a fluent context menu with actions to pin/unpin the window across all desktops or close it.
- Middle-clicking a window card or clicking its close button terminates the window.
- Dragging a window card dynamically scales it down; hovering over a workspace card highlights the drop target, and releasing moves the window to that workspace via Hyprland dispatch.
- Clicking any workspace switches desktops and smoothly closes the overview. Clicking "New desktop" switches to an empty workspace.
- Pressing Escape, clicking the backdrop, or clicking outside (via HyprlandFocusGrab) smoothly plays the exit transition (workspace bar slides down, window cards fade, keyboard focus yields to underlying windows).
- Screen lock immediately suppresses and closes the overview.

**Edge states.**
- Empty workspace: Shows empty grid space and centers the workspace switcher bar smoothly.
- Zero/corrupt window geometry: Guarded by fallback dimensions in `window-layout.js`.
- Multiple monitors: Hosted per screen with focused monitor grab coordination.
- Screen locked: Inhibits opening and dismisses immediately.

**Cost.**
- Eliminates offscreen GPU frame captures when overview is idle by gating `ScreencopyView.live` to `GlobalStates.overviewOpen`.
- Uses standard elementMoveEnter / elementMoveExit curves without extraneous offscreen passes.

**Delete.**
- Removed dead scaffold properties (`searchingText`, `dontAutoCancelSearch`).
- Removed redundant nested `wsBg` Rectangle.
- Removed buggy immediate `root.closed()` destroy bypass in workspace click handler.

**Out of scope.**
- Backend Hyprland window tiling math or compositor rendering pipeline.
