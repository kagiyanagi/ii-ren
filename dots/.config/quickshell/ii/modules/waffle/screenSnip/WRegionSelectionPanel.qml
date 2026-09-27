pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.utils
import qs.modules.common.widgets
import qs.modules.waffle.looks

PanelWindow {
    id: root

    enum MediaType {
        Image,
        Video
    }
    enum ImageAction {
        Copy,
        Menu,
        CharRecognition,
        Search,
        QrScan
    }
    enum VideoAction {
        Record,
        RecordWithSound
    }
    enum SelectionMode {
        Rect,
        Window
    }

    property bool open: true
    signal fadedOut()
    signal dismiss()

    function close() {
        root.dismiss();
    }

    onOpenChanged: {
        if (!root.open && (!root.visible || content.opacity === 0))
            root.fadedOut();
    }

    readonly property bool passive: !root.open || !root.preparationDone
    WlrLayershell.keyboardFocus: root.passive ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand
    mask: root.passive ? passthroughRegion : null
    Region { id: passthroughRegion }

    property var mediaType: WRegionSelectionPanel.MediaType.Image
    property var imageAction: WRegionSelectionPanel.ImageAction.Copy
    property var videoAction: WRegionSelectionPanel.VideoAction.Record
    property var selectionMode: WRegionSelectionPanel.SelectionMode.Rect

    visible: false
    color: "transparent"
    WlrLayershell.namespace: "quickshell:regionSelector"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }

    // Hyprland monitors and active workspace
    readonly property HyprlandMonitor hyprlandMonitor: Hyprland.monitorFor(screen)
    readonly property real monitorScale: hyprlandMonitor?.scale ?? 1.0
    readonly property real monitorOffsetX: hyprlandMonitor?.x ?? 0
    readonly property real monitorOffsetY: hyprlandMonitor?.y ?? 0
    property int activeWorkspaceId: hyprlandMonitor?.activeWorkspace?.id ?? (HyprlandData.activeWorkspace?.id ?? 0)
    readonly property var windows: [...HyprlandData.windowList].sort((a, b) => {
        // Sort floating=true windows before others
        if (a.floating === b.floating)
            return 0;
        return a.floating ? -1 : 1;
    })

    property string screenshotDir: Directories.screenshotTemp
    property string screenshotPath: `${root.screenshotDir}/image-${root.screen?.name ?? "default"}.ppm`
    TempScreenshotProcess {
        id: screenshotProc
        running: true
        screen: root.screen
        screenshotDir: root.screenshotDir
        screenshotPath: root.screenshotPath
        onExited: (exitCode, exitStatus) => {
            root.preparationDone = true;
        }
    }
    property bool preparationDone: false
    onPreparationDoneChanged: {
        if (!preparationDone)
            return;
        root.visible = true;
    }

    function getScreenshotAction() {
        switch (root.mediaType) {
        case WRegionSelectionPanel.MediaType.Image:
            switch (root.imageAction) {
            case WRegionSelectionPanel.ImageAction.Copy:
                return ScreenshotAction.Action.Copy;
            case WRegionSelectionPanel.ImageAction.Menu:
                return ScreenshotAction.Action.Edit;
            case WRegionSelectionPanel.ImageAction.CharRecognition:
                return ScreenshotAction.Action.CharRecognition;
            case WRegionSelectionPanel.ImageAction.Search:
                return ScreenshotAction.Action.Search;
            case WRegionSelectionPanel.ImageAction.QrScan:
                return ScreenshotAction.Action.QrScan;
            default:
                return ScreenshotAction.Action.Copy;
            }
        case WRegionSelectionPanel.MediaType.Video:
            switch (root.videoAction) {
            case WRegionSelectionPanel.VideoAction.Record:
                return ScreenshotAction.Action.Record;
            case WRegionSelectionPanel.VideoAction.RecordWithSound:
                return ScreenshotAction.Action.RecordWithSound;
            default:
                return ScreenshotAction.Action.Record;
            }
        default:
            return ScreenshotAction.Action.Copy;
        }
    }

    Item {
        id: content
        anchors.fill: parent

        property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
        opacity: {
            content.fadeSpec = root.open ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
            return root.visible && root.open ? 1 : 0;
        }
        Behavior on opacity {
            NumberAnimation {
                duration: content.fadeSpec.duration
                easing.type: content.fadeSpec.type
                easing.bezierCurve: content.fadeSpec.bezierCurve
            }
        }
        onOpacityChanged: {
            if (content.opacity === 0 && !root.open)
                root.fadedOut();
        }

        ScreencopyView {
            id: screencopyView
            anchors.fill: parent
            live: false
            captureSource: root.screen

            focus: root.visible && !root.passive
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.dismiss();
                } else if (event.key === Qt.Key_E && (event.modifiers & Qt.ControlModifier)) {
                    if (root.imageAction === WRegionSelectionPanel.ImageAction.Menu) {
                        root.imageAction = WRegionSelectionPanel.ImageAction.Copy;
                    } else {
                        root.imageAction = WRegionSelectionPanel.ImageAction.Menu;
                    }
                }
            }

            DragManager {
                id: dragArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.CrossCursor
                enabled: !root.passive

                property bool isWindowSelection: root.selectionMode === WRegionSelectionPanel.SelectionMode.Window
                property var hoveredWindow: {
                    if (!isWindowSelection)
                        return null;
                    return root.windows.find(w => {
                        const inCurrentWorkspace = w.workspace.id === root.activeWorkspaceId;
                        const winX = w.at[0] - root.monitorOffsetX;
                        const winY = w.at[1] - root.monitorOffsetY;
                        const withinXRange = winX <= dragArea.mouseX && dragArea.mouseX <= winX + w.size[0];
                        const withinYRange = winY <= dragArea.mouseY && dragArea.mouseY <= winY + w.size[1];
                        return inCurrentWorkspace && withinXRange && withinYRange;
                    });
                }
                property int rawSelectionX: isWindowSelection ? ((hoveredWindow?.at[0] ?? root.monitorOffsetX) - root.monitorOffsetX) : regionTopLeftX
                property int rawSelectionY: isWindowSelection ? ((hoveredWindow?.at[1] ?? root.monitorOffsetY) - root.monitorOffsetY) : regionTopLeftY
                property int rawSelectionWidth: isWindowSelection ? (hoveredWindow ? hoveredWindow.size[0] : 0) : regionWidth
                property int rawSelectionHeight: isWindowSelection ? (hoveredWindow ? hoveredWindow.size[1] : 0) : regionHeight

                property int selectionX: Math.max(0, rawSelectionX)
                property int selectionY: Math.max(0, rawSelectionY)
                property int selectionWidth: Math.max(0, Math.min(root.screen.width, rawSelectionX + rawSelectionWidth) - selectionX)
                property int selectionHeight: Math.max(0, Math.min(root.screen.height, rawSelectionY + rawSelectionHeight) - selectionY)

                onDragReleased: (diffX, diffY) => {
                    if (selectionWidth <= 0 || selectionHeight <= 0) {
                        return;
                    }
                    const screenshotDir = Config.options.screenSnip.savePath !== "" ? Config.options.screenSnip.savePath : "";
                    const screenshotAction = root.getScreenshotAction();
                    if (screenshotAction === undefined) {
                        return;
                    }
                    const command = ScreenshotAction.getCommand(
                        dragArea.selectionX * root.monitorScale,
                        dragArea.selectionY * root.monitorScale,
                        dragArea.selectionWidth * root.monitorScale,
                        dragArea.selectionHeight * root.monitorScale,
                        root.screenshotPath,
                        screenshotAction,
                        screenshotDir
                    );
                    Quickshell.execDetached(command);
                    root.dismiss();
                }

                WRectangularSelection {
                    id: rectangularSelection
                    anchors.fill: parent
                    regionX: dragArea.selectionX
                    regionY: dragArea.selectionY
                    regionWidth: dragArea.selectionWidth
                    regionHeight: dragArea.selectionHeight
                    dashed: root.selectionMode === WRegionSelectionPanel.SelectionMode.Rect
                }

                RegionSelectionOptionsToolbar {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.open && root.visible ? 12 : -implicitHeight - 24
                    Behavior on y {
                        NumberAnimation {
                            duration: root.open ? Appearance.animation.elementMoveFast.duration : Appearance.animation.elementMoveExit.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: root.open ? Looks.transition.easing.bezierCurve.easeIn : Looks.transition.easing.bezierCurve.easeOut
                        }
                    }
                }
            }
        }
    }

    component RegionSelectionOptionsToolbar: WToolbar {
        // Image/video
        WToolbarTabBar {
            currentIndex: switch (root.mediaType) {
            case WRegionSelectionPanel.MediaType.Image:
                return 0;
            case WRegionSelectionPanel.MediaType.Video:
                return 1;
            default:
                return 0;
            }
            WToolbarIconTabButton {
                icon.name: "camera"
                icon.color: Looks.colors.fg
            }
            WToolbarIconTabButton {
                icon.name: "video"
                icon.color: Looks.colors.fg
            }
            onCurrentIndexChanged: {
                switch (currentIndex) {
                case 0:
                    root.mediaType = WRegionSelectionPanel.MediaType.Image;
                    break;
                case 1:
                    root.mediaType = WRegionSelectionPanel.MediaType.Video;
                    break;
                }
            }

            WToolTip {
                text: Translation.tr("Snip")
            }
        }

        // Selection type
        WToolbarButton {
            id: selectionTypeBtn
            implicitWidth: selectionTypeBtnRow.implicitWidth + 12 * 2
            leftPadding: 12
            rightPadding: 12
            onClicked: {
                selectionTypeMenu.visible = !selectionTypeMenu.visible;
            }
            contentItem: Row {
                id: selectionTypeBtnRow
                spacing: 4
                FluentIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: switch (root.selectionMode) {
                    case WRegionSelectionPanel.SelectionMode.Rect:
                        return "crop";
                    case WRegionSelectionPanel.SelectionMode.Window:
                        return "desktop";
                    default:
                        return "crop";
                    }
                    implicitSize: 18
                }
                FluentIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "chevron-down"
                    implicitSize: 12
                }
            }

            WMenu {
                id: selectionTypeMenu
                downDirection: true
                onClosed: screencopyView.focus = true
                y: selectionTypeBtn.height + 4
                color: Looks.colors.bg1Base

                Action {
                    icon.name: "crop"
                    text: Translation.tr("Rectangle")
                    checked: root.selectionMode === WRegionSelectionPanel.SelectionMode.Rect
                    onTriggered: {
                        root.selectionMode = WRegionSelectionPanel.SelectionMode.Rect;
                    }
                }
                Action {
                    icon.name: "desktop"
                    text: Translation.tr("Window")
                    checked: root.selectionMode === WRegionSelectionPanel.SelectionMode.Window
                    onTriggered: {
                        root.selectionMode = WRegionSelectionPanel.SelectionMode.Window;
                    }
                }
            }

            WToolTip {
                text: Translation.tr("Snipping area")
            }
        }

        // Markup
        WToolbarIconButton {
            icon.name: "image-edit"
            enabled: root.mediaType === WRegionSelectionPanel.MediaType.Image
            checked: root.imageAction === WRegionSelectionPanel.ImageAction.Menu
            onClicked: {
                if (root.imageAction === WRegionSelectionPanel.ImageAction.Menu) {
                    root.imageAction = WRegionSelectionPanel.ImageAction.Copy;
                } else {
                    root.imageAction = WRegionSelectionPanel.ImageAction.Menu;
                }
            }
            WToolTip {
                text: Translation.tr("Quick markup (Ctrl+E)")
            }
        }

        WToolbarSeparator {}

        // Tools
        WToolbarIconButton {
            icon.name: "search-visual"
            checked: root.imageAction === WRegionSelectionPanel.ImageAction.Search
            onClicked: {
                if (root.imageAction === WRegionSelectionPanel.ImageAction.Search && root.mediaType === WRegionSelectionPanel.MediaType.Image) {
                    root.imageAction = WRegionSelectionPanel.ImageAction.Copy;
                } else {
                    root.mediaType = WRegionSelectionPanel.MediaType.Image;
                    root.imageAction = WRegionSelectionPanel.ImageAction.Search;
                }
            }
            WToolTip {
                text: Translation.tr("Image search")
            }
        }
        WToolbarIconButton {
            icon.name: "eyedropper"
            onClicked: {
                Quickshell.execDetached(["bash", "-c", "sleep 0.2; hyprpicker -a"]);
                root.dismiss();
            }
            WToolTip {
                text: Translation.tr("Color picker")
            }
        }
        WToolbarIconButton {
            icon.name: "scan-text"
            checked: root.imageAction === WRegionSelectionPanel.ImageAction.CharRecognition
            onClicked: {
                if (root.imageAction === WRegionSelectionPanel.ImageAction.CharRecognition && root.mediaType === WRegionSelectionPanel.MediaType.Image) {
                    root.imageAction = WRegionSelectionPanel.ImageAction.Copy;
                } else {
                    root.mediaType = WRegionSelectionPanel.MediaType.Image;
                    root.imageAction = WRegionSelectionPanel.ImageAction.CharRecognition;
                }
            }
            WToolTip {
                text: Translation.tr("Text extractor")
            }
        }

        WToolbarSeparator {}

        WToolbarIconButton {
            icon.name: "dismiss"
            onClicked: root.dismiss()
            WToolTip {
                text: Translation.tr("Close (Esc)")
            }
        }
    }
}
