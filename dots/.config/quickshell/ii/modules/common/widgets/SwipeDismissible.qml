import qs.modules.common
import QtQuick

/**
 * Swipe-to-dismiss for a row. Slides `target`'s left margin by `xOffset` and
 * fires `dismissed()` once the row has slid past `dragConfirmThreshold`.
 *
 * `owner`'s grandparent (`qmlParent`) is a broadcast point so sibling rows can
 * make way while one of them drags -- that needs `dragIndex`/`dragDistance`/
 * `resetDrag`, the contract `StyledListView` implements. It is guessed
 * structurally (`owner.parent.parent`) but declared as a plain `property`, not
 * `readonly`, so a caller whose shared state lives somewhere else can set it
 * directly instead.
 *
 * An owner with no such ancestor -- a lone card, not a list row -- still gets
 * a correct self-dismiss: `xOffset`'s own-row branch reads this instance's
 * `dragDiffX` directly rather than bouncing through the parent, and every
 * write to `qmlParent` is gated on `hasSharedDragState`, so a `qmlParent` that
 * does not actually implement the contract is a no-op, not a crash (see
 * .audit/ii-clipboardToast/notes.md, which hit exactly this and hand-rolled
 * its own dismiss instead). Neighbour-follow -- the 0.3/0.1 fractions -- only
 * ever fires with a real shared parent; a lone item has no neighbours to move.
 *
 * DESIGN.md 3.6: nothing here fades -- this widget only tracks the gesture. A
 * caller that wants the dragged row to lift takes `dragging` and animates its
 * own elevation / 0.16 `colLayerNActive` tint from it.
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

    property var qmlParent: root.owner?.parent?.parent // There's something between this and the parent ListView
    // True only when `qmlParent` actually implements the shared-drag contract,
    // not just when it resolves to *something*. The structural guess above
    // lands on a real Item outside a ListView too -- one with none of these
    // members -- and writing/calling through it unguarded is how a lone card
    // used to crash instead of dismissing.
    readonly property bool hasSharedDragState: typeof root.qmlParent?.resetDrag === "function"
    readonly property var parentDragIndex: qmlParent?.dragIndex ?? -1
    readonly property var parentDragDistance: qmlParent?.dragDistance ?? 0
    readonly property var dragIndexDiff: Math.abs(parentDragIndex - root.itemIndex)
    // The own-row branch (dragIndexDiff == 0, true with no qmlParent at all --
    // both sides default to -1) reads this instance's own live diff rather
    // than the parent's broadcast copy, so a row with no shared parent still
    // slides under its own finger. Identical value to the old
    // `parentDragDistance` read whenever a real parent exists, since this is
    // the row that wrote that broadcast copy in the first place.
    readonly property real xOffset: dragIndexDiff == 0 ? root.dragDiffX :
        Math.abs(parentDragDistance) > dragConfirmThreshold ? 0 :
        dragIndexDiff == 1 ? (parentDragDistance * 0.3) :
        dragIndexDiff == 2 ? (parentDragDistance * 0.1) : 0

    function destroyWithAnimation(left = false) {
        if (root.hasSharedDragState)
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
        if (dragging && root.hasSharedDragState) {
            root.qmlParent.dragIndex = root.itemIndex;
        }
    }

    onDragDiffXChanged: () => {
        if (root.hasSharedDragState)
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
