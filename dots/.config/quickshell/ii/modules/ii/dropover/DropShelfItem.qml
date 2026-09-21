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

    // The name-and-icon layout is both the fallback for a file that is not an
    // image and the one for an image that will not load, so a file deleted out
    // from under the shelf leaves a name rather than an empty frame. Only
    // `isImage` may reach `source`: deriving it from `status` instead makes the
    // failure clear the source, which clears the status, which restores it.
    readonly property bool showImage: root.isImage && thumbnail.status === Image.Ready

    // A tile cannot be dragged with the keyboard, but it can be taken off the
    // shelf, and until this the pointer was the only way to remove one
    // (DESIGN.md 3.7).
    activeFocusOnTab: true
    Keys.onDeletePressed: DropShelf.removeItem(root.path)

    Rectangle {
        id: tile

        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: Appearance.colors.colSurfaceContainerHighest
        clip: true

        StyledImage {
            id: thumbnail

            anchors.fill: parent
            visible: root.showImage
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
            spacing: 4
            // Nothing while an image is still decoding: the icon would show for a
            // frame and then be replaced by the thumbnail.
            visible: !root.isImage || thumbnail.status === Image.Error

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "draft"
                iconSize: 40
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

        // Composited rather than a swapped fill, so the states read the same over
        // a photo as over the empty tile (DESIGN.md 3.1).
        StateOverlay {
            anchors.fill: parent
            radius: tile.radius
            contentColor: Appearance.colors.colOnLayer1
            hover: dragArea.containsMouse
            focused: root.activeFocus
            press: dragArea.containsPress
            drag: dragArea.drag.active
        }
    }

    MouseArea {
        id: dragArea

        anchors.fill: parent
        hoverEnabled: true
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

    // Middle click is the only other way off the shelf and nothing announces it,
    // so the tile grows a remove affordance under the pointer. 32 square is the
    // hit-target floor (3.4); it is out of the way while the tile is in flight.
    RippleButton {
        id: removeButton

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 4
        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        // The card's own surface, floated over the tile: the tile is already
        // colSurfaceContainerHighest, so a chip on the same token disappears on
        // every tile that is not a photo.
        colBackground: Appearance.colors.colLayer0
        opacity: (dragArea.containsMouse || root.activeFocus) && !dragArea.drag.active ? 1 : 0
        visible: opacity > 0
        onClicked: DropShelf.removeItem(root.path)

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "close"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer1
        }

        // Hover-driven, so it has to reverse mid-flight rather than finish
        // (DESIGN.md 2.7) -- a pointer flicked along the strip would otherwise
        // leave every tile it crossed playing a full fade in and out.
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this, {
                alwaysRunToEnd: false
            })
        }
    }

    // Only the tile that was actually pressed hands its drag to the proxy.
    Binding {
        target: root.dragProxy
        property: "dragging"
        value: dragArea.drag.active
        when: root.dragProxy.path === root.path
    }
}
