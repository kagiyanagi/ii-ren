import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root

    property alias sidebarLeftOpen: root.policiesPanelOpen // Until all sidebars naming is fixed
    property alias sidebarRightOpen: root.dashboardPanelOpen // Until all sidebars naming is fixed

    // ── Desktop widget library (ported from ii-p3drovfx) ─────────────────────
    // Its widgets read these. Two map onto state this shell already has.
    property alias lockScreenCentered: root.screenLocked
    function openRightSidebar(): void { root.dashboardPanelOpen = true; }

    // The rest are surfaces p3 has and this shell does not, or holds elsewhere:
    // the cheatsheet and notes live in their own Loaders, not in GlobalStates.
    // ponytail: stubs, so the widgets bind and render; the handful of buttons
    // that write them are inert. Bind Cheatsheet/Notes loaders to these if the
    // buttons turn out to matter.
    property alias lockAnimationActive: root.screenLocked

    // ── Lock screen widget drags ─────────────────────────────────────────────
    // A session lock surface is above every layer shell, so a desktop widget
    // never sees the lock screen's pointer. Widgets register themselves here so
    // the proxy in LockSurface can forward the gesture into the real widget
    // rather than keep a second copy of its position. Keyed screen|instanceId.
    readonly property var lockDragTargets: ({})
    property int lockDragTargetsVersion: 0
    function registerLockDragTarget(key: string, item: Item): void {
        root.lockDragTargets[key] = item;
        root.lockDragTargetsVersion++;
    }
    function unregisterLockDragTarget(key: string): void {
        delete root.lockDragTargets[key];
        root.lockDragTargetsVersion++;
    }
    property bool workspaceRestoreInProgress: false
    property bool cheatsheetOpen: false
    property bool notesOpen: false
    property bool requestVolumeDialog: false

    property bool alarmRinging: false
    property bool barOpen: true
    property bool crosshairOpen: false
    property bool mediaControlsOpen: false
    property bool immersiveMediaOpen: false
    property int barMediaCount: 0
    property int dockMediaCount: 0
    readonly property bool barMediaConfigured: {
        if (!Config.ready || !Config.options?.bar?.layouts) return false;
        const l = Config.options.bar.layouts;
        const hasPlayer = list => (list || []).some(item => item?.id === "music_player" && item?.visible !== false);
        return (hasPlayer(l.left) || hasPlayer(l.center) || hasPlayer(l.right)) && root.barOpen;
    }
    readonly property bool barMediaPresent: root.barOpen && (barMediaConfigured || barMediaCount > 0)
    readonly property bool dockMediaConfigured: (Config.options?.dock?.enable ?? false) && (Config.options?.dock?.enableMediaWidget ?? false)
    readonly property bool dockMediaPresent: (Config.options?.dock?.enable ?? false) && (dockMediaConfigured || dockMediaCount > 0)
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screenTranslatorOpen: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false

    // Vertical space the notification popups currently take up, so other panels
    // sharing that corner can move out of their way. 0 when none are showing.
    property real notificationPopupHeight: 0

    // Configurable popup heights and corners so they can stack if they share a corner
    property real fastPairPopupHeight: 0
    property string fastPairPopupCorner: ""
    
    property real clipboardToastHeight: 0
    property string clipboardToastCorner: ""
    
    property real screenshotPreviewHeight: 0
    property string screenshotPreviewCorner: ""

    // Desktop right-click menu, positioned at the click.
    property bool desktopMenuOpen: false
    property var desktopMenuScreen: null
    property real desktopMenuX: 0
    property real desktopMenuY: 0
    property var desktopMenuWidgetId: null

    // Drop shelf, positioned at the point the files were dropped. -1 means the
    // shelf was opened without one and should centre itself.
    property bool dropShelfOpen: false
    property real dropShelfX: -1
    property real dropShelfY: -1

    property bool dashboardPanelOpen: false // formerly sidebarRightOpen
    property bool policiesPanelOpen: false  // formerly sidebarLeftOpen

    readonly property bool effectiveLeftOpen: {
        switch (Config.options.sidebar.position) {
            case "default":  return policiesPanelOpen;  
            case "inverted": return dashboardPanelOpen;  
            case "left":     return dashboardPanelOpen || policiesPanelOpen;
            case "right":    return false;
            default:         return policiesPanelOpen;
        }
    }
    readonly property bool effectiveRightOpen: {
        switch (Config.options.sidebar.position) {
            case "default":  return dashboardPanelOpen; 
            case "inverted": return policiesPanelOpen; 
            case "left":     return false;
            case "right":    return dashboardPanelOpen || policiesPanelOpen;
            default:         return dashboardPanelOpen;
        }
    }

    // helper properties
    readonly property bool policiesOnLeft: Config.options.sidebar.position === "default" || Config.options.sidebar.position === "left"
    readonly property bool dashboardOnLeft: Config.options.sidebar.position === "inverted" || Config.options.sidebar.position === "left"

    onPoliciesPanelOpenChanged: {
        if (policiesPanelOpen) {
            if (Config.options.sidebar.position == "right" || Config.options.sidebar.position == "left") {
                GlobalStates.dashboardPanelOpen = false
            }
        }
        
    }

    onDashboardPanelOpenChanged: {
        if (dashboardPanelOpen) {
            Notifications.timeoutAll();
            Notifications.markAllRead();
            if (Config.options.sidebar.position == "right" || Config.options.sidebar.position == "left") {
                GlobalStates.policiesPanelOpen = false
            }
        }
        
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"
        onPressed: {
            root.superDown = true
        }
        onReleased: {
            root.superDown = false
        }
    }
}