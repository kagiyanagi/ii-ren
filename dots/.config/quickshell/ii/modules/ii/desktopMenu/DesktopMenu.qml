pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
// ponytail: DockMenuButton is a generic icon + label menu row with nothing dock
// specific in it. Move it to common/widgets if a third menu wants it.
import qs.modules.ii.dock
import qs.services
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    IpcHandler {
        target: "desktopMenu"

        // No cursor to open at, so centre it on the focused monitor.
        function toggle(): void {
            if (GlobalStates.desktopMenuOpen) {
                GlobalStates.desktopMenuOpen = false;
                return;
            }
            const screen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
            GlobalStates.desktopMenuScreen = screen;
            GlobalStates.desktopMenuX = screen.width / 2;
            GlobalStates.desktopMenuY = screen.height / 2;
            GlobalStates.desktopMenuOpen = true;
        }
    }

    Loader {
        active: GlobalStates.desktopMenuOpen

        sourceComponent: PanelWindow {
            id: menuWindow

            function hide(): void {
                GlobalStates.desktopMenuOpen = false;
            }

            screen: GlobalStates.desktopMenuScreen ?? Quickshell.screens[0]
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:desktopMenu"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Anywhere off the card dismisses, which is what a context menu does.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: menuWindow.hide()
            }

            StyledRectangularShadow {
                target: menuCard
            }

            Rectangle {
                id: menuCard

                readonly property real gutter: 8

                // Opens with its top-left at the cursor, like every other context
                // menu, and slides back inside the screen near an edge.
                x: Math.max(gutter, Math.min(GlobalStates.desktopMenuX, menuWindow.width - width - gutter))
                y: Math.max(gutter, Math.min(GlobalStates.desktopMenuY, menuWindow.height - height - gutter))

                implicitWidth: 280
                implicitHeight: menuColumn.implicitHeight + 2 * menuColumn.anchors.margins
                radius: Appearance.rounding.verylarge
                color: Appearance.m3colors.m3surfaceContainer

                opacity: 0
                scale: 0.96
                transformOrigin: Item.TopLeft
                Component.onCompleted: {
                    menuCard.opacity = 1;
                    menuCard.scale = 1;
                }

                // Both on the 200ms curve. elementMoveEnter is 400ms of
                // deceleration, which reads as the menu still arriving well after
                // it is already clickable.
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                // Swallows the clicks the dismiss handler underneath would take.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                ColumnLayout {
                    id: menuColumn

                    // Reshuffled on every open, since the whole component is
                    // rebuilt per right click. The current one leads so its check
                    // mark is always on screen without scrolling.
                    // isValidImageByName also drops the subdirectories the model
                    // carries, which have no thumbnail to show.
                    // Snapshotted, not bound: picking a wallpaper writes the config
                    // back, and a live read here would reshuffle the strip and yank
                    // the tile out from under the pointer.
                    property string initialWallpaper: ""
                    Component.onCompleted: menuColumn.initialWallpaper = Config.options.background.wallpaperPath

                    readonly property var shuffledWallpapers: {
                        const current = menuColumn.initialWallpaper;
                        const rest = Wallpapers.wallpapers.filter(path => Images.isValidImageByName(path.toLowerCase()) && path !== current);
                        for (let i = rest.length - 1; i > 0; i--) {
                            const j = Math.floor(Math.random() * (i + 1));
                            [rest[i], rest[j]] = [rest[j], rest[i]];
                        }
                        return Images.isValidImageByName(current.toLowerCase()) ? [current, ...rest] : rest;
                    }

                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 0

                    focus: true
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape)
                            menuWindow.hide();
                    }

                    Item {
                        id: stripViewport

                        Layout.fillWidth: true
                        Layout.preferredHeight: 108
                        Layout.bottomMargin: 8
                        visible: wallpaperStrip.count > 0

                        // The viewport cuts the tiles at each end square, so round
                        // the cut itself the same as the tiles.
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: stripViewport.width
                                height: stripViewport.height
                                radius: Appearance.rounding.normal
                            }
                        }

                        ListView {
                            id: wallpaperStrip

                            // Set on click so the tile grows right away; switchwall
                            // writing the config back is a good second later. The
                            // Connections puts it back in sync with reality after.
                            property string selectedPath: Config.options.background.wallpaperPath

                            Connections {
                                target: Config.options.background
                                function onWallpaperPathChanged(): void {
                                    wallpaperStrip.selectedPath = Config.options.background.wallpaperPath;
                                }
                            }

                            anchors.fill: parent
                            orientation: ListView.Horizontal
                            spacing: 6
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: menuColumn.shuffledWallpapers

                            delegate: Item {
                                id: wallpaperTile

                                required property string modelData
                                readonly property bool current: modelData === wallpaperStrip.selectedPath

                                // The one in use gets the wider tile, like the launcher's.
                                // The list repositions its neighbours every frame of
                                // this, so the whole strip slides along with it.
                                width: current ? 124 : 80
                                Behavior on width {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                height: wallpaperStrip.height

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colSurfaceContainerHigh
                                }

                                ThumbnailImage {
                                    id: wallpaperThumbnail
                                    anchors.fill: parent
                                    sourcePath: wallpaperTile.modelData
                                    fillMode: Image.PreserveAspectCrop
                                    // Cropping paints past the item, and the layer the
                                    // rounding mask sits on grows with it, so the top
                                    // corners come out square without this.
                                    clip: true
                                    // A tile this size crops a landscape wallpaper down
                                    // to its middle, so both the cached thumbnail and the
                                    // decode have to be bigger than the tile itself or it
                                    // is all upscale.
                                    thumbnailSizeName: "x-large"
                                    sourceSize: Qt.size(0, height * 2)
                                    layer.enabled: true
                                    layer.effect: OpacityMask {
                                        maskSource: Rectangle {
                                            width: wallpaperThumbnail.width
                                            height: wallpaperThumbnail.height
                                            radius: Appearance.rounding.normal
                                        }
                                    }
                                }

                                // Scrim, because a light wallpaper under a light
                                // accent leaves the check mark invisible.
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Appearance.rounding.normal
                                    color: Qt.rgba(0, 0, 0, 0.35)

                                    opacity: wallpaperTile.current ? 1 : 0
                                    visible: opacity > 0
                                    Behavior on opacity {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        implicitWidth: 26
                                        implicitHeight: 26
                                        radius: Appearance.rounding.full
                                        color: Appearance.colors.colPrimary

                                        scale: wallpaperTile.current ? 1 : 0.5
                                        Behavior on scale {
                                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                        }

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "check"
                                            iconSize: 16
                                            color: Appearance.m3colors.m3onPrimary
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    // Stays open, so several can be tried in a row.
                                    onClicked: {
                                        wallpaperStrip.selectedPath = wallpaperTile.modelData;
                                        Wallpapers.apply(wallpaperTile.modelData);
                                    }
                                }
                            }
                        }

                        // Softens the tile the viewport cuts in half at each end.
                        ScrollEdgeFade {
                            target: wallpaperStrip
                            vertical: false
                            fadeSize: 28
                            color: Appearance.m3colors.m3surfaceContainer
                        }

                        // A horizontal Flickable ignores a vertical wheel, so the
                        // strip only scrolls by dragging without this.
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            onWheel: event => {
                                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                                wallpaperStrip.contentX = Math.max(0, Math.min(wallpaperStrip.contentX - delta, wallpaperStrip.contentWidth - wallpaperStrip.width));
                            }
                        }
                    }

                    DockMenuButton {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        symbolName: "wallpaper"
                        labelText: Translation.tr("Change wallpaper")
                        onTriggered: {
                            menuWindow.hide();
                            GlobalStates.wallpaperSelectorOpen = true;
                        }
                    }

                    DockMenuButton {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        symbolName: "shuffle"
                        labelText: Translation.tr("Random wallpaper")
                        onTriggered: {
                            menuWindow.hide();
                            Wallpapers.randomFromCurrentFolder();
                        }
                    }

                    DockMenuButton {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        symbolName: "folder_open"
                        labelText: Translation.tr("Open wallpaper file...")
                        onTriggered: {
                            menuWindow.hide();
                            Wallpapers.openFallbackPicker();
                        }
                    }

                    DockMenuButton {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        symbolName: "stacks"
                        labelText: DropShelf.items.length > 0
                            ? Translation.tr("Drop shelf (%1)").arg(DropShelf.items.length)
                            : Translation.tr("Drop shelf")
                        onTriggered: {
                            menuWindow.hide();
                            // Reuse the click point so the shelf lands where the
                            // menu was, not back at the last drop.
                            GlobalStates.dropShelfX = GlobalStates.desktopMenuX;
                            GlobalStates.dropShelfY = GlobalStates.desktopMenuY;
                            GlobalStates.dropShelfOpen = true;
                        }
                    }

                    DockMenuButton {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        symbolName: "settings"
                        labelText: Translation.tr("Settings")
                        onTriggered: {
                            menuWindow.hide();
                            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("settings.qml")]);
                        }
                    }
                }
            }
        }
    }
}
