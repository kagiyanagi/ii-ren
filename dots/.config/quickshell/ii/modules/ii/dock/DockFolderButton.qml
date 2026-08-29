pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import "./widgets"

DockButton {
    id: root

    property var dockContent: null
    property var folder: null
    property int folderIndex: -1

    readonly property var appIds: Array.from(folder?.apps ?? [])
    readonly property string folderName: folder?.name || qsTr("Folder")
    readonly property real dockHeightPx: Config.options?.dock.height ?? 60
    readonly property int dotMargin: Math.round(root.dockHeightPx * 0.2)

    // Open, the folder gets out of the way of its own card and leaves the dot
    // the dock already uses to say "this one is live".
    readonly property bool cardOpen: (dock.folderCard?.active ?? false) && dock.folderCard.folderIndex === root.folderIndex

    width: buttonSize + dotMargin * 2
    height: buttonSize + dotMargin * 2

    releaseAction: () => {
        root.bounce();
        dock.folderCard.open(root, root.folderIndex);
    }
    altAction: () => folderContextMenu.open()

    DockContextMenuBase {
        id: folderContextMenu
        anchorItem: root
        headerSymbol: "folder"
        headerText: root.folderName

        contentComponent: ColumnLayout {
            spacing: 0

            DockMenuButton {
                Layout.fillWidth: true
                symbolName: "folder_open"
                labelText: qsTr("Open")
                onTriggered: {
                    folderContextMenu.close();
                    dock.folderCard.open(root, root.folderIndex);
                }
            }

            DockMenuButton {
                Layout.fillWidth: true
                symbolName: "folder_delete"
                labelText: qsTr("Delete folder")
                isDestructive: true
                onTriggered: {
                    TaskbarApps.removeFolder(root.folderIndex);
                    folderContextMenu.close();
                }
            }
        }
    }

    Connections {
        target: folderContextMenu
        function onActiveChanged() {
            if (root.dockContent)
                root.dockContent.anyContextMenuOpen = folderContextMenu.active;
        }
    }

    DockTooltip {
        parentItem: root
        text: root.folderName
        showTooltip: root.hovered && !root.cardOpen && !(root.dockContent?.dragActive ?? false)
    }

    contentItem: Item {
        anchors.fill: parent

        Item {
            id: folderIcon
            anchors.centerIn: parent
            implicitWidth: root.buttonSize
            implicitHeight: root.buttonSize

            scale: root.cardOpen ? 0.2 : 1
            opacity: root.cardOpen ? 0 : 1
            Behavior on scale {
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            MaterialShape {
                anchors.centerIn: parent
                implicitSize: Math.round(root.buttonSize * 0.88)
                shape: MaterialShape.Shape.Circle
                color: root.hovered ? Appearance.colors.colLayer1Hover : Appearance.colors.colSurfaceContainerHigh

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            // Deliberately outside the shape and unclipped: at this size the
            // grid's corners spill past the circle, which is the launcher look.
            Grid {
                anchors.centerIn: parent
                columns: 2
                spacing: Math.round(root.buttonSize * 0.04)

                Repeater {
                    model: root.appIds.slice(0, 4)

                    delegate: DockIcon {
                        required property string modelData
                        appId: modelData
                        isRunning: true
                        width: Math.round(root.buttonSize * 0.46)
                        height: width
                    }
                }
            }
        }

        // The open folder collapses to a dot in the dock's indicator colour,
        // round and at icon scale rather than the running-window dash.
        Rectangle {
            anchors.centerIn: parent
            implicitWidth: Math.round(root.buttonSize * 0.42)
            implicitHeight: implicitWidth
            width: implicitWidth
            height: implicitHeight
            radius: Appearance.rounding.full
            color: Appearance.colors.colPrimary

            scale: root.cardOpen ? 1 : 0
            opacity: root.cardOpen ? 1 : 0
            Behavior on scale {
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
