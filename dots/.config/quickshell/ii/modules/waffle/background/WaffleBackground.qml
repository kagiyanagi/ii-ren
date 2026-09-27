pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks

Variants {
    id: root
    model: Config.options.background.enable ? Quickshell.screens : []

    PanelWindow {
        id: panelRoot
        required property var modelData

        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:background"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Hyprland monitor & workspace tracking for fullscreen hiding
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
        readonly property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && panelRoot.monitor && workspace.monitor.name === panelRoot.monitor.name)
        readonly property var activeWorkspaceWithFullscreen: workspacesForMonitor.find(workspace => workspace.active && workspace.toplevels.values.some(window => window.wayland?.fullscreen))
        readonly property bool hasFullscreenWindow: activeWorkspaceWithFullscreen !== undefined
        visible: GlobalStates.screenLocked || !hasFullscreenWindow || !Config.options.background.hideWhenFullscreen

        // Wallpaper paths & video detection
        readonly property bool wallpaperIsVideo: Wallpapers.isVideoFile(Config.options.background.wallpaperPath.toLowerCase())
        readonly property string wallpaperPath: panelRoot.wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath

        // Workplace / sensitive network safety guard
        readonly property bool wallpaperSafetyTriggered: {
            const enabled = Config.options.workSafety.enable.wallpaper;
            const sensitiveWallpaper = StringUtils.stringListContainsSubstring(panelRoot.wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords);
            const sensitiveNetwork = StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords);
            return enabled && sensitiveWallpaper && sensitiveNetwork;
        }

        color: {
            if (!panelRoot.wallpaperSafetyTriggered || panelRoot.wallpaperIsVideo)
                return "transparent";
            return Looks.colors.bg0;
        }
        Behavior on color {
            animation: Looks.transition.color.createObject(this)
        }

        TransitionImage {
            anchors.fill: parent
            visible: !panelRoot.wallpaperIsVideo
            imageSource: panelRoot.wallpaperSafetyTriggered ? "" : panelRoot.wallpaperPath
            fillMode: Image.PreserveAspectCrop
        }

        MouseArea {
            id: desktopMenuArea
            anchors.fill: parent
            enabled: Config.options.background.rightClickMenu
            acceptedButtons: Qt.RightButton

            onPressed: mouse => {
                GlobalStates.desktopMenuWidgetId = null;
                GlobalStates.desktopMenuScreen = panelRoot.screen;
                GlobalStates.desktopMenuX = mouse.x;
                GlobalStates.desktopMenuY = mouse.y;
                GlobalStates.desktopMenuOpen = true;
            }
        }

        DropArea {
            id: wallpaperDrop
            anchors.fill: parent
            keys: ["text/uri-list"]
            enabled: Config.options.background.dropToSetWallpaper || Config.options.background.dropToShelf

            property string pendingPath: ""
            property int pendingShelfCount: 0

            function localPaths(urls) {
                const paths = [];
                for (const url of urls) {
                    const asString = url.toString();
                    const path = FileUtils.trimFileProtocol(asString);
                    if (path === asString)
                        continue;
                    paths.push(path);
                }
                return paths;
            }

            function wallpaperPathFrom(paths) {
                if (!Config.options.background.dropToSetWallpaper || paths.length !== 1)
                    return "";
                const path = paths[0];
                return Wallpapers.extensions.some(ext => path.toLowerCase().endsWith(`.${ext}`)) ? path : "";
            }

            onEntered: drag => {
                const paths = drag.hasUrls ? wallpaperDrop.localPaths(drag.urls) : [];
                wallpaperDrop.pendingPath = wallpaperDrop.wallpaperPathFrom(paths);
                wallpaperDrop.pendingShelfCount = (wallpaperDrop.pendingPath.length > 0 || !Config.options.background.dropToShelf) ? 0 : paths.length;
                if (wallpaperDrop.pendingPath.length === 0 && wallpaperDrop.pendingShelfCount === 0)
                    drag.accepted = false;
            }

            onExited: {
                wallpaperDrop.pendingPath = "";
                wallpaperDrop.pendingShelfCount = 0;
            }

            onDropped: drop => {
                if (wallpaperDrop.pendingPath.length > 0) {
                    Wallpapers.apply(wallpaperDrop.pendingPath);
                    drop.acceptProposedAction();
                } else if (wallpaperDrop.pendingShelfCount > 0) {
                    DropShelf.show(drop.urls, panelRoot.screen, drop.x, drop.y);
                    drop.acceptProposedAction();
                }
                wallpaperDrop.pendingPath = "";
                wallpaperDrop.pendingShelfCount = 0;
            }

            Rectangle {
                id: dropHint
                anchors.centerIn: parent
                implicitWidth: dropHintRow.implicitWidth + 40
                implicitHeight: dropHintRow.implicitHeight + 28
                radius: Looks.radius.large
                color: Looks.colors.bg1Base
                border.width: 1
                border.color: Looks.colors.accent

                readonly property bool shown: wallpaperDrop.containsDrag
                    && (wallpaperDrop.pendingPath.length > 0 || wallpaperDrop.pendingShelfCount > 0)

                visible: opacity > 0
                opacity: shown ? 1 : 0
                scale: shown ? 1 : 0.9

                Behavior on opacity {
                    animation: Looks.transition.opacity.createObject(this)
                }
                Behavior on scale {
                    animation: Looks.transition.enter.createObject(this)
                }

                RowLayout {
                    id: dropHintRow
                    anchors.centerIn: parent
                    spacing: 12

                    FluentIcon {
                        icon: wallpaperDrop.pendingPath.length > 0 ? "image" : "library"
                        implicitSize: 24
                        color: Looks.colors.accent
                    }

                    ColumnLayout {
                        spacing: 0

                        WText {
                            text: wallpaperDrop.pendingPath.length > 0
                                ? Translation.tr("Set as wallpaper")
                                : Translation.tr("Hold on the shelf")
                            color: Looks.colors.fg
                            font.weight: Looks.font.weight.strong
                        }

                        WText {
                            Layout.maximumWidth: 320
                            text: wallpaperDrop.pendingPath.length > 0
                                ? wallpaperDrop.pendingPath.split("/").pop()
                                : Translation.tr("%1 files").arg(wallpaperDrop.pendingShelfCount)
                            color: Looks.colors.subfg
                            font.pixelSize: Looks.font.pixelSize.normal
                            elide: Text.ElideMiddle
                        }
                    }
                }
            }
        }
    }
}
