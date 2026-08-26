import qs.modules.common
import QtQuick

/**
 * Swipe-to-dismiss for a list row. Slides `target`'s left margin, nudges the
 * neighbouring rows through the parent ListView's dragIndex/dragDistance, and
 * fires `dismissed()` once the row has slid off screen.
 *
 * Drops in where the row's DragManager was, so it keeps the same single
 * MouseArea and the same place in the child stacking order. The row still owns
 * `anchors`, `interactive` and `acceptedButtons`.
 */
DragManager {
    id: root
    automaticallyReset: false

    required property Item owner // The row root
    required property Item target // The row background that slides
    // The row's ListView index. Passed in because a bare `index` only resolves
    // in the delegate's own document.
    property int itemIndex: -1
    property real dragConfirmThreshold: 70 // Drag further to discard notification
    property real dismissOvershoot: 20 // Account for gaps and bouncy animations

    signal dismissed()

    readonly property var qmlParent: root.owner?.parent?.parent // There's something between this and the parent ListView
    readonly property var parentDragIndex: qmlParent?.dragIndex ?? -1
    readonly property var parentDragDistance: qmlParent?.dragDistance ?? 0
    readonly property var dragIndexDiff: Math.abs(parentDragIndex - root.itemIndex)
    readonly property real xOffset: dragIndexDiff == 0 ? parentDragDistance :
        Math.abs(parentDragDistance) > dragConfirmThreshold ? 0 :
        dragIndexDiff == 1 ? (parentDragDistance * 0.3) :
        dragIndexDiff == 2 ? (parentDragDistance * 0.1) : 0

    function destroyWithAnimation(left = false) {
        root.qmlParent.resetDrag()
        root.target.anchors.leftMargin = root.target.anchors.leftMargin; // Break binding
        destroyAnimation.left = left;
        destroyAnimation.running = true;
    }

    onClicked: (mouse) => {
        if (mouse.button === Qt.MiddleButton) {
            root.destroyWithAnimation();
        }
    }

    onDraggingChanged: () => {
        if (dragging) {
            root.qmlParent.dragIndex = root.itemIndex;
        }
    }

    onDragDiffXChanged: () => {
        root.qmlParent.dragDistance = dragDiffX;
    }

    onDragReleased: (diffX, diffY) => {
        if (Math.abs(diffX) > root.dragConfirmThreshold)
            root.destroyWithAnimation(diffX < 0);
        else
            root.resetDrag();
    }

    SequentialAnimation { // Drag finish animation
        id: destroyAnimation
        property bool left: true
        running: false

        NumberAnimation {
            target: root.target.anchors
            property: "leftMargin"
            to: (root.owner.width + root.dismissOvershoot) * (destroyAnimation.left ? -1 : 1)
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
        onFinished: root.dismissed()
    }
}
