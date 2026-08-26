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

                implicitWidth: 260
                implicitHeight: menuColumn.implicitHeight + 16
                radius: Appearance.rounding.normal
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
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 0

                    focus: true
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape)
                            menuWindow.hide();
                    }

                    DockMenuButton {
                        Layout.fillWidth: true
                        symbolName: "wallpaper"
                        labelText: Translation.tr("Change wallpaper")
                        onTriggered: {
                            menuWindow.hide();
                            GlobalStates.wallpaperSelectorOpen = true;
                        }
                    }

                    DockMenuButton {
                        Layout.fillWidth: true
                        symbolName: "shuffle"
                        labelText: Translation.tr("Random wallpaper")
                        onTriggered: {
                            menuWindow.hide();
                            Wallpapers.randomFromCurrentFolder();
                        }
                    }

                    DockMenuButton {
                        Layout.fillWidth: true
                        symbolName: "folder_open"
                        labelText: Translation.tr("Open wallpaper file...")
                        onTriggered: {
                            menuWindow.hide();
                            Wallpapers.openFallbackPicker();
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        Layout.bottomMargin: 4
                        implicitHeight: 1
                        color: Appearance.colors.colLayer0Border
                    }

                    DockMenuButton {
                        Layout.fillWidth: true
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
