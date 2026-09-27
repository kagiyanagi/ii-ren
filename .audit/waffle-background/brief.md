# waffle-background — brief

**Purpose.** The desktop background surface for the Waffle panel family (Windows 11 Fluent style). Renders the static or animated wallpaper layer, supports animated wallpaper transitions, handles video wallpapers, ensures click-through / right-click menu integration, provides drag-and-drop file operations (wallpaper drop and DropShelf integration), and suspends background rendering when occluded by fullscreen windows.

**Primary action.** Passive visual canvas; context action: right-clicking the desktop to trigger `DesktopMenu`; drag-and-drop: dragging an image to set wallpaper or multiple files onto the desktop to store in `DropShelf`.

**Hierarchy.**
1. **Variants**: Spawns one `PanelWindow` per screen in `Quickshell.screens` (gated on `Config.options.background.enable`).
2. **PanelWindow**: Anchored fullscreen on `WlrLayer.Bottom`, `exclusionMode: Ignore`, `quickshell:background` namespace.
3. **TransitionImage**: Wallpaper surface supporting radial/wipe/fade animated transitions between wallpaper updates.
4. **MouseArea**: Right-click listener bound to `Config.options.background.rightClickMenu` invoking `DesktopMenu`.
5. **DropArea**: Drag-and-drop target for images (set wallpaper) and files (staged onto `DropShelf`) with Fluent-styled drop hint.

**Reference.** Windows 11 desktop canvas combined with ii-ren design tokens and Fluent styling (`modules/waffle/looks/Looks.qml`).

**What is wrong, measured.**
- **Dead & Inappropriate Imports.** Copied unused imports from `modules/ii/background/Background.qml`, including `widgetCanvas`, `Qt5Compat.GraphicalEffects`, `Quickshell.Io`, and leaked ii-specific widgets (`qs.modules.ii.background.widgets.*`).
- **Unconditional Panel Loading in `WaffleFamily.qml`.** Loaded `PanelLoader { component: WaffleBackground {} }` without `extraCondition: Config.options.background.enable`. Disabling the background in settings (e.g. to use `hyprpaper`, `swww`, or `mpvpaper` externally) did not prevent `WaffleBackground` from spawning surfaces.
- **Missing Fullscreen Occlusion Hiding.** Did not observe `Config.options.background.hideWhenFullscreen` or active fullscreen windows on the monitor, needlessly consuming GPU resources to render and blend wallpaper behind opaque fullscreen games or video players.
- **Uncaught Video Wallpaper Errors.** Bound directly to `Config.options.background.wallpaperPath` in `StyledImage`. When the user configured a video wallpaper (`.mp4`, `.webm`, `.mkv`), `StyledImage` failed with image decoding errors and occluded the underlying `mpvpaper` output.
- **No Wallpaper Transitions.** Used static `StyledImage` instead of `TransitionImage`, causing abrupt jumps when switching wallpapers instead of honoring `Config.options.background.animateWallpaperChanges` and transition styles.
- **Ignored Work Safety Mode.** Failed to check `Config.options.workSafety.enable.wallpaper` and network/filename keywords, risking displaying sensitive wallpapers on public Wi-Fi or workplaces.
- **Non-functional Right-Click & Desktop Drag-and-Drop.** Right-clicking the desktop did nothing because neither a context listener nor `DesktopMenu` was wired up. Dragging image files or items onto the desktop was completely unhandled.

**Interaction.**
- Desktop right-click opens `DesktopMenu` at cursor coordinates (`Qt.RightButton`).
- Dragging an image onto the desktop previews "Set as wallpaper" with `FluentIcon` ("image"); releasing applies the wallpaper via `Wallpapers.apply()`.
- Dragging multiple files previews "Hold on the shelf" with `FluentIcon` ("library"); releasing opens `DropShelf`.
- Switching wallpapers animates smoothly using `TransitionImage`.

**Edge states.**
- Fullscreen window active on monitor: `WaffleBackground` sets `visible: false` when `hideWhenFullscreen` is true.
- Video wallpaper active: `TransitionImage` is hidden (`visible: !wallpaperIsVideo`) and surface is transparent so `mpvpaper` renders cleanly without QML image errors.
- Work safety triggered: wallpaper is blanked and surface takes `Looks.colors.bg0` neutral tint.
- Screen locked: remains visible or cleanly occluded by `WlSessionLockSurface`.

**Cost.**
- Saves compositor blending overhead during fullscreen windows.
- Prevents image decode errors on video wallpapers.

**Delete.**
- Removed 7 unused/leaked imports (`widgetCanvas`, `Layouts`, `GraphicalEffects`, `Quickshell.Io`, `clock`, `weather`, `widgets`).
- Replaced static `StyledImage` with `TransitionImage`.

**Out of scope.**
- Re-architecting wallpaper backend scripts (`switchwall.sh`) or Hyprland IPC monitors.
