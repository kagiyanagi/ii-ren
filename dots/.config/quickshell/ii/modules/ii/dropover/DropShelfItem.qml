pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

// One shelf tile. The outgoing drag itself belongs to the panel's DragProxy, not
// to this delegate: QDrag::exec runs a nested event loop, so a delegate that got
// destroyed part-way through a drag would free the mime data the compositor is
// still reading from, and take the shell down with it.
Item {
    id: root

    required property string path
    required property DragProxy dragProxy

    readonly property string fileName: root.path.split("/").pop()
    readonly property bool isImage: /\.(png|jpe?g|webp|bmp|gif|avif)$/i.test(root.path)

    Rectangle {
        id: tile
        anchors.fill: parent
        anchors.margins: 2
        radius: Appearance.rounding.normal
        color: Appearance.colors.colSurfaceContainerHighest
        clip: true

        StyledImage {
            anchors.fill: parent
            visible: root.isImage
            source: root.isImage ? `file://${root.path}` : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            // Without this a dropped 4K wallpaper is decoded at full size for a
            // 96px tile, which is what stalls the shelf as it opens.
            sourceSize.width: width * 2
            sourceSize.height: height * 2
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width - 12
            spacing: 2
            visible: !root.isImage

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "draft"
                iconSize: 32
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.fileName
                elide: Text.ElideMiddle
                maximumLineCount: 2
                wrapMode: Text.WrapAnywhere
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer1
            }
        }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        cursorShape: Qt.OpenHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        // The proxy is what moves, so the threshold and the drag both happen off
        // this delegate.
        drag.target: root.dragProxy

        onPressed: event => {
            if (event.button === Qt.LeftButton)
                root.dragProxy.arm(root.path, tile);
        }

        // Middle click is the quick way to take one item back off the shelf.
        onClicked: event => {
            if (event.button === Qt.MiddleButton)
                DropShelf.removeItem(root.path);
        }

        onReleased: root.dragProxy.disarm()
    }

    // Only the tile that was actually pressed hands its drag to the proxy.
    Binding {
        target: root.dragProxy
        property: "dragging"
        value: dragArea.drag.active
        when: root.dragProxy.path === root.path
    }
}
