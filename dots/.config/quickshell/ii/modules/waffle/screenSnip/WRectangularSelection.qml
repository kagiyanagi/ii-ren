pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks

Item {
    id: root

    required property int regionX
    required property int regionY
    required property int regionWidth
    required property int regionHeight

    property bool dashed: true
    property color borderColor: Looks.colors.accent
    property color overlayColor: Appearance.colors.colScrim

    // Overlay to darken screen
    // Base dark overlay around region
    Rectangle {
        id: darkenOverlay
        z: 1
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: root.regionX - border.width
            topMargin: root.regionY - border.width
        }
        width: root.regionWidth + border.width * 2
        height: root.regionHeight + border.width * 2
        color: "transparent"
        border.color: root.overlayColor
        border.width: Math.max(root.width, root.height)
    }

    // Selection border
    Rectangle {
        id: selectionBorder
        z: 2
        visible: root.regionWidth > 0 && root.regionHeight > 0
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: Math.round(root.regionX - border.width)
            topMargin: Math.round(root.regionY - border.width)
        }
        width: Math.round(root.regionWidth + border.width * 2)
        height: Math.round(root.regionHeight + border.width * 2)
        color: "transparent"
        border.color: root.borderColor
        border.width: 1
    }
}
