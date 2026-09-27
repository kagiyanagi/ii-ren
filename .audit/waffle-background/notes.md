# waffle-background — notes

Audited and refactored `WaffleBackground.qml` under `modules/waffle/background/` and integrated fallbacks in `panelFamilies/WaffleFamily.qml`.

## Findings

1. **Dead Imports & Leaked ii-Specific Modules:**
   `WaffleBackground.qml` inherited unused imports from `Background.qml`:
   - `qs.modules.common.widgets.widgetCanvas`
   - `QtQuick.Layouts` (now only used in `DropArea` dropHint)
   - `Qt5Compat.GraphicalEffects`
   - `Quickshell.Io`
   - `qs.modules.ii.background.widgets`
   - `qs.modules.ii.background.widgets.clock`
   - `qs.modules.ii.background.widgets.weather`
   Removed all unnecessary and leaked ii-specific imports; imported `qs.modules.waffle.looks`, `qs.modules.common.functions`, and required quickshell/qt singletons.

2. **Unconditional Panel Loading:**
   `WaffleFamily.qml` previously loaded `WaffleBackground` without `extraCondition`. Users disabling the background to use external wallpaper managers (hyprpaper, swww, feh) still had the quickshell surface spawned.
   - Added `extraCondition: Config.options.background.enable` to `PanelLoader` in `WaffleFamily.qml`.
   - Gated `Variants` model on `Config.options.background.enable ? Quickshell.screens : []` for standalone safety.

3. **Fullscreen Occlusion Power Saving:**
   Added monitor and active workspace fullscreen window detection (`Hyprland.monitorFor`, `workspacesForMonitor`, and `activeWorkspaceWithFullscreen`).
   When `Config.options.background.hideWhenFullscreen` is enabled, the background sets `visible: false` while a fullscreen window occupies the workspace, eliminating unnecessary GPU drawing and blending overhead. Added null guards for `panelRoot.monitor`.

4. **Video Wallpaper Support:**
   `WaffleBackground.qml` previously bound directly to `Config.options.background.wallpaperPath`, attempting to load `.mp4`/`.webm`/`.mkv` videos into `StyledImage` and failing with decode errors while blocking `mpvpaper`.
   - Added `wallpaperIsVideo: Wallpapers.isVideoFile(...)` detection.
   - Hides the image element (`visible: !panelRoot.wallpaperIsVideo`) and ensures `panelRoot.color: "transparent"` so the underlying `mpvpaper` layer-shell surface displays cleanly.

5. **Animated Wallpaper Transitions:**
   Replaced static `StyledImage` with `TransitionImage`, enabling animated wallpaper crossfades/radial wipes according to `Config.options.background.animateWallpaperChanges` and transition timing tokens.

6. **Work Safety Wallpaper Protection:**
   Integrated `Config.options.workSafety` checks matching `Background.qml`. If `wallpaperSafetyTriggered` is true on sensitive networks with flagged filenames:
   - Blanks the wallpaper `imageSource: ""`.
   - Tints the background to neutral `Looks.colors.bg0` with smooth transition animation (`Looks.transition.color`).

7. **Desktop Right-Click Context Menu:**
   Added `MouseArea` listening on `Qt.RightButton` with `enabled: Config.options.background.rightClickMenu`. Right-clicking opens `DesktopMenu` at cursor coordinates (`GlobalStates.desktopMenuOpen = true`).
   Added `DesktopMenu` fallback loader to `WaffleFamily.qml` gated on `Config.options.background.rightClickMenu`.

8. **Drag-and-Drop Operations & Fluent Drop Hint:**
   Added `DropArea` supporting:
   - Dropping a single image file to immediately set wallpaper via `Wallpapers.apply()`.
   - Dropping multiple files to stage them in `DropShelf` (`DropShelf.show()`).
   - Fluent-styled drop hint overlay built with `Looks` design tokens (`Looks.radius.large`, `Looks.colors.bg1Base`, `Looks.colors.accent`), `Looks.transition` animations, `FluentIcon`, and `WText`.
   - Added `DropShelfPanel` fallback loader to `WaffleFamily.qml`.

## Verification

- **Automated Gate (`tools/check-waffle-background.py`):**
  Asserts `pragma ComponentBehavior: Bound`, import hygiene, null-safe fullscreen hiding, video wallpaper handling, work safety guard, `TransitionImage` usage, right-click menu integration, drag-and-drop support, Fluent design tokens in drop hint, and `WaffleFamily.qml` gating/fallbacks. Passed with 0 errors.
- **Design Check (`tools/check-design.py --diff`):**
  0 findings, 0 errors.
- **Effect Budget (`tools/check-effect-budget.py`):**
  0 findings, passed cleanly.
