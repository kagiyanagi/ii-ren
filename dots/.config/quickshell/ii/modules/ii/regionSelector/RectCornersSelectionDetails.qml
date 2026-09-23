import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Item {
    id: root
    required property real regionX
    required property real regionY
    required property real regionWidth
    required property real regionHeight
    required property real mouseX
    required property real mouseY
    required property color color
    required property color overlayColor
    property bool showAimLines: Config.options.regionSelector.rect.showAimLines

    // A drag under way, or a region being recorded - not a click, whose region
    // is zero-sized until it lands on a target, and "0 × 0" is noise.
    property bool showSelection: false
    // Recording: the scrim, the label and the aim lines go, the border stays.
    property bool borderOnly: false

    // Overlay to darken screen
    // Base dark overlay around region
    Rectangle {
        id: darkenOverlay
        z: 1
        visible: !root.borderOnly
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: root.regionX - darkenOverlay.border.width
            topMargin: root.regionY - darkenOverlay.border.width
        }
        width: root.regionWidth + darkenOverlay.border.width * 2
        height: root.regionHeight + darkenOverlay.border.width * 2
        color: "transparent"
        border.color: root.overlayColor
        border.width: Math.max(root.width, root.height)
    }

    // Solid, as SystemUI's CropView frames a crop, and the same 2px as a
    // target at rest. Drawn just outside the region, so a recording of it
    // never includes it. A Rectangle, not DashedBorder: that is a Canvas,
    // which clears, strokes and re-uploads a texture the size of the
    // selection on every pointer move of a drag.
    Rectangle {
        id: selectionBorder
        z: 9
        visible: root.showSelection
        x: Math.round(root.regionX) - border.width
        y: Math.round(root.regionY) - border.width
        width: Math.round(root.regionWidth) + border.width * 2
        height: Math.round(root.regionHeight) + border.width * 2
        color: "transparent"
        border.color: root.color
        border.width: 2
    }

    StyledText {
        z: 2
        visible: root.showSelection && !root.borderOnly
        readonly property real gap: 8
        readonly property real below: selectionBorder.y + selectionBorder.height + gap
        // Under the region's bottom-right corner, above it when the region
        // reaches the bottom of the screen, and never off either side.
        x: Math.max(gap, selectionBorder.x + selectionBorder.width - width - gap)
        y: below + height + gap <= root.height ? below : Math.max(gap, selectionBorder.y - height - gap)
        color: root.color
        font.family: Appearance.font.family.numbers
        text: `${Math.round(root.regionWidth)} × ${Math.round(root.regionHeight)}`
    }

    // Coord lines
    Rectangle { // Vertical
        visible: root.showAimLines && !root.borderOnly
        opacity: 0.2
        z: 2
        x: root.mouseX
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        width: 1
        color: root.color
    }
    Rectangle { // Horizontal
        visible: root.showAimLines && !root.borderOnly
        opacity: 0.2
        z: 2
        y: root.mouseY
        anchors {
            left: parent.left
            right: parent.right
        }
        height: 1
        color: root.color
    }
}
