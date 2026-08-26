pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: dropoverScope

    IpcHandler {
        target: "dropShelf"

        function toggle(): void {
            if (GlobalStates.dropShelfOpen) {
                DropShelf.hide();
                return;
            }
            // No stored drop point to reopen at, so centre it.
            GlobalStates.dropShelfX = -1;
            GlobalStates.dropShelfY = -1;
            GlobalStates.dropShelfOpen = true;
        }

        // Lets a script or keybind put something on the shelf without a drag.
        function add(path: string): void {
            DropShelf.addItems([`file://${path}`]);
            GlobalStates.dropShelfOpen = true;
        }

        function remove(path: string): void {
            DropShelf.removeItem(path);
        }

        function clear(): void {
            DropShelf.clear();
        }

        function copy(): void {
            DropShelf.copyAll();
        }
    }

    PanelWindow {
        id: root

        visible: GlobalStates.dropShelfOpen && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:dropShelf"
        WlrLayershell.layer: WlrLayer.Overlay

        readonly property real gutter: 20

        // Full-screen surface with a masked-out card: the shelf grows and shrinks
        // as items come and go, and reconfiguring a layer surface every frame is
        // what makes that stutter.
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        mask: Region {
            item: shelfCard
        }

        Rectangle {
            id: shelfCard

            // -1 means "no drop point" (opened from IPC), so centre it instead.
            x: GlobalStates.dropShelfX < 0
                ? (root.width - width) / 2
                : Math.max(root.gutter, Math.min(root.width - width - root.gutter, GlobalStates.dropShelfX - width / 2))
            y: GlobalStates.dropShelfY < 0
                ? (root.height - height) / 2
                : Math.max(root.gutter, Math.min(root.height - height - root.gutter, GlobalStates.dropShelfY - height - 30))

            implicitWidth: 360
            implicitHeight: contentColumn.implicitHeight + 24
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            // Dropping onto the shelf itself piles more on rather than replacing.
            DropArea {
                anchors.fill: parent
                keys: ["text/uri-list"]

                onEntered: drag => drag.accepted = drag.hasUrls

                onDropped: drop => {
                    if (!drop.hasUrls) {
                        drop.accepted = false;
                        return;
                    }
                    DropShelf.addItems(drop.urls);
                    drop.acceptProposedAction();
                }
            }

            DragProxy {
                id: shelfDragProxy
            }

            ColumnLayout {
                id: contentColumn
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 108
                    orientation: ListView.Horizontal
                    spacing: 8
                    clip: true
                    model: DropShelf.items
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: DropShelfItem {
                        required property string modelData
                        path: modelData
                        dragProxy: shelfDragProxy
                        implicitWidth: 96
                        implicitHeight: 108
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("%1 items").arg(DropShelf.items.length)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        buttonRadius: height / 2
                        buttonText: Translation.tr("Copy")
                        enabled: DropShelf.items.length > 0
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: DropShelf.copyAll()
                    }

                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        buttonRadius: height / 2
                        buttonText: Translation.tr("Clear")
                        onClicked: DropShelf.clear()
                    }

                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        buttonRadius: height / 2
                        buttonText: Translation.tr("Close")
                        onClicked: DropShelf.hide()
                    }
                }
            }
        }

        StyledRectangularShadow {
            target: shelfCard
            z: -1
        }
    }
}
