import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// One display on the arrangement canvas. Dragging moves it in compositor
// coordinates, snapping its edges to the other displays.
Rectangle {
    id: root

    required property var monitor
    required property int monitorIndex
    required property var monitorConfig
    required property real scaleFactor
    required property point canvasOffset
    required property var allMonitors
    property bool isSelected: false
    property var previewPositions: ({})
    property bool hasOverlap: false

    signal monitorClicked(int index)
    signal positionDragging(int index, int x, int y)
    signal positionCommitted(int index, int x, int y)

    property bool isDragging: false
    property real dragX: 0
    property real dragY: 0
    property int snappedX: 0
    property int snappedY: 0
    // Pixels on screen, not compositor pixels, so the pull feels the same at
    // any zoom level.
    readonly property real snapThreshold: 12

    readonly property int logW: root.monitorConfig?.logicalWidth(root.monitor) ?? 0
    readonly property int logH: root.monitorConfig?.logicalHeight(root.monitor) ?? 0

    x: root.isDragging ? root.dragX : (root.previewPositions[root.monitor.name]?.x ?? root.monitor.x) * root.scaleFactor + root.canvasOffset.x
    y: root.isDragging ? root.dragY : (root.previewPositions[root.monitor.name]?.y ?? root.monitor.y) * root.scaleFactor + root.canvasOffset.y
    width: root.logW * root.scaleFactor
    height: root.logH * root.scaleFactor

    radius: Appearance.rounding.small
    z: root.isDragging ? 100 : root.isSelected ? 2 : 1

    // Hover, focus, press and drag are the state film below, not this: a
    // dragged display used to drop to 0.7 alpha, and 3.6 says a dragged item
    // lifts rather than fades. Overlap is a semantic error fill, not a state,
    // so it stays here - as the error *container* role, not a half-alpha
    // m3error (6.1).
    color: {
        if (root.monitor.disabled) return Appearance.colors.colLayer2;
        if (root.isDragging && root.hasOverlap) return Appearance.colors.colErrorContainer;
        if (root.isSelected) return Appearance.colors.colPrimaryContainer;
        return Appearance.colors.colSecondaryContainer;
    }
    border.color: (root.isDragging && root.hasOverlap) ? Appearance.colors.colError
        : (root.isDragging || root.isSelected) ? Appearance.colors.colPrimary
        : Appearance.colors.colLayer0Border
    border.width: (root.isDragging || root.isSelected) ? 2 : 1

    // The lift that replaces the fade. Spatial, so it may overshoot, and it
    // grows from the centre of the tile the pointer is holding (2.6).
    scale: root.isDragging ? 1.03 : 1
    transformOrigin: Item.Center

    Behavior on x { enabled: !root.isDragging; animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
    Behavior on y { enabled: !root.isDragging; animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
    Behavior on scale { animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this) }
    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

    // All four states (3.1) - the canvas had hover only, and nothing at all for
    // a keyboard. StateOverlay composites them independently so hover -> press
    // -> drag stays continuous while the pointer holds the tile.
    StateOverlay {
        anchors.fill: parent
        topLeftRadius: root.radius
        topRightRadius: root.radius
        bottomLeftRadius: root.radius
        bottomRightRadius: root.radius
        contentColor: root.monitor.disabled ? Appearance.colors.colSubtext
            : root.isSelected ? Appearance.colors.colOnPrimaryContainer
            : Appearance.colors.colOnSecondaryContainer
        hover: hoverArea.containsMouse && !hoverArea.pressed
        focused: root.activeFocus
        press: hoverArea.pressed && !root.isDragging
        drag: root.isDragging
    }

    // Reachable without a pointer (3.7): Tab walks the displays, Enter or Space
    // selects the one under focus.
    activeFocusOnTab: !root.monitor.disabled
    Keys.onPressed: event => {
        if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Space)
            return;
        root.monitorClicked(root.monitorIndex);
        event.accepted = true;
    }

    // Outline of where the drag would land after snapping.
    Rectangle {
        visible: root.isDragging && !root.hasOverlap
        x: root.snappedX * root.scaleFactor + root.canvasOffset.x - root.x
        y: root.snappedY * root.scaleFactor + root.canvasOffset.y - root.y
        width: root.width
        height: root.height
        radius: root.radius
        color: "transparent"
        border.color: Appearance.colors.colPrimary
        border.width: 2
        opacity: 0.6
    }

    Column {
        anchors.centerIn: parent
        spacing: 2

        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.monitor.disabled ? "desktop_access_disabled" : "desktop_windows"
            iconSize: Math.min(20, Math.min(root.width, root.height) * 0.25)
            color: root.monitor.disabled ? Appearance.colors.colSubtext
                : root.isSelected ? Appearance.colors.colOnPrimaryContainer
                : Appearance.colors.colPrimary
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, root.width - 8)
            text: root.monitor?.name ?? ""
            // Shrinks with the tile but never off the token ladder (7).
            font.pixelSize: Math.max(Appearance.font.pixelSize.smallest, Math.min(Appearance.font.pixelSize.smallie, root.width * 0.1))
            font.weight: Font.Medium
            color: root.monitor.disabled ? Appearance.colors.colSubtext
                : root.isSelected ? Appearance.colors.colOnPrimaryContainer
                : Appearance.colors.colOnSecondaryContainer
            elide: Text.ElideMiddle
            horizontalAlignment: Text.AlignHCenter
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: `${root.logW}x${root.logH}`
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
            horizontalAlignment: Text.AlignHCenter
        }
    }

    function snapPosition(px: real, py: real): point {
        let sx = px;
        let sy = py;
        const thresh = root.snapThreshold / root.scaleFactor;
        for (let i = 0; i < root.allMonitors.length; i++) {
            if (i === root.monitorIndex) continue;
            const other = root.allMonitors[i];
            if (other.disabled) continue;
            const ow = root.monitorConfig.logicalWidth(other);
            const oh = root.monitorConfig.logicalHeight(other);
            if (Math.abs(px - other.x) < thresh) sx = other.x;
            if (Math.abs(px - (other.x + ow)) < thresh) sx = other.x + ow;
            if (Math.abs((px + root.logW) - other.x) < thresh) sx = other.x - root.logW;
            if (Math.abs((px + root.logW) - (other.x + ow)) < thresh) sx = other.x + ow - root.logW;
            if (Math.abs(py - other.y) < thresh) sy = other.y;
            if (Math.abs(py - (other.y + oh)) < thresh) sy = other.y + oh;
            if (Math.abs((py + root.logH) - other.y) < thresh) sy = other.y - root.logH;
            if (Math.abs((py + root.logH) - (other.y + oh)) < thresh) sy = other.y + oh - root.logH;
        }
        return Qt.point(sx, sy);
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: !root.monitor.disabled
        cursorShape: root.monitor.disabled ? Qt.ArrowCursor
            : root.isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        drag.target: root
        drag.axis: Drag.XAndYAxis
        drag.threshold: 4

        onPressed: {
            root.dragX = root.monitor.x * root.scaleFactor + root.canvasOffset.x;
            root.dragY = root.monitor.y * root.scaleFactor + root.canvasOffset.y;
            root.snappedX = root.monitor.x;
            root.snappedY = root.monitor.y;
            root.isDragging = true;
        }
        onPositionChanged: {
            if (!root.isDragging) return;
            root.dragX = root.x;
            root.dragY = root.y;
            const snapped = root.snapPosition(
                Math.round((root.x - root.canvasOffset.x) / root.scaleFactor),
                Math.round((root.y - root.canvasOffset.y) / root.scaleFactor));
            root.snappedX = snapped.x;
            root.snappedY = snapped.y;
            root.positionDragging(root.monitorIndex, root.snappedX, root.snappedY);
        }
        onReleased: {
            root.isDragging = false;
            // Didn't actually move: treat it as a click to select instead.
            if (root.snappedX === root.monitor.x && root.snappedY === root.monitor.y) {
                root.monitorClicked(root.monitorIndex);
                return;
            }
            root.positionCommitted(root.monitorIndex, root.snappedX, root.snappedY);
        }
    }
}
