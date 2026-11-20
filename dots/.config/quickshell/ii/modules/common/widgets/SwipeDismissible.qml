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
 * does not actually implement the contract is a no-op, not a crash (the
 * clipboard toast hit exactly this and hand-rolled its own dismiss instead).
 * Neighbour-follow -- the 0.3/0.1 fractions -- only
 * ever fires with a real shared parent; a lone item has no neighbours to move.
 *
 * DESIGN.md 3.6: nothing fades while it is dragged -- a caller that wants the
 * dragged row to lift takes `dragging` and animates its own elevation / 0.16
 * `colLayerNActive` tint from it. Leaving is another matter: `fadeOnDismiss`
 * fades the owner out over the escape, for a card floating over the desktop
 * (the notification popup) that would otherwise slide into the window's slack
 * still opaque and vanish when its row is removed.
 *
 * The gesture is AOSP SwipeHelper's, as SwipeToDismiss's is: it locks to the
 * horizontal axis past the touch slop (DragManager.lockToXAxis), goes once it
 * has travelled `dragConfirmThreshold` or been flung past `escapeVelocity` the
 * way it was going, and leaves at the speed it was thrown -- linearly, so the
 * throw carries straight on; a release with no speed in it accelerates away.
 *
 * Drops in where the row's DragManager was, so it keeps the same single
 * MouseArea and the same place in the child stacking order. The row still owns
 * `anchors`, `interactive` and `acceptedButtons`.
 */
DragManager {
    id: root
    automaticallyReset: false
    lockToXAxis: true

    required property Item owner // The row root
    required property Item target // The row background that slides
    // The row's ListView index. Passed in because a bare `index` only resolves
    // in the delegate's own document.
    property int itemIndex: -1
    property real dragConfirmThreshold: 70 // Drag further to discard notification
    property real dismissOvershoot: 20 // Account for gaps and bouncy animations
    property bool fadeOnDismiss: false

    // SwipeHelper: SWIPE_ESCAPE_VELOCITY, DEFAULT_ESCAPE_ANIMATION_DURATION,
    // MAX_ESCAPE_ANIMATION_DURATION -- the values SwipeToDismiss uses.
    readonly property real escapeVelocity: 500
    readonly property int escapeDurationDefault: 200
    readonly property int escapeDurationMax: 400
    // A pointer that stopped this long before letting go was not thrown.
    readonly property int velocityStaleMs: 100

    // px/s along x, smoothed over the last few moves of the drag.
    property real velocityX: 0
    property real _lastDiffX: 0
    property double _lastMoveTime: 0

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

    function destroyWithAnimation(left = false, velocity = 0) {
        if (root.hasSharedDragState)
            root.qmlParent.resetDrag()
        const from = root.target.anchors.leftMargin;
        root.target.anchors.leftMargin = from; // Break binding
        const to = (root.owner.width + root.dismissOvershoot) * (left ? -1 : 1);
        destroyAnimation.to = to;
        destroyAnimation.thrown = velocity !== 0;
        destroyAnimation.escapeDuration = velocity !== 0 ?
            Math.min(root.escapeDurationMax, Math.abs(to - from) * 1000 / Math.abs(velocity)) :
            root.escapeDurationDefault;
        destroyAnimation.restart();
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
        const now = Date.now();
        const dt = now - root._lastMoveTime;
        if (dt > 0) {
            const v = (root.dragDiffX - root._lastDiffX) * 1000 / dt;
            root.velocityX = dt > root.velocityStaleMs ? v : (root.velocityX + v) / 2;
        }
        root._lastDiffX = root.dragDiffX;
        root._lastMoveTime = now;
    }

    // The row can go away in the middle of a drag -- a popup expiring under the
    // finger, a group closing, the model dropping it. `dragReleased` never
    // arrives, so nothing hands the broadcast back, and `dragDistance` stays at
    // whatever the vanished row last wrote: every surviving neighbour keeps its
    // 0.3 / 0.1 nudge for as long as the list lives. That is the notification
    // that sits half a swipe to the right and will not come back.
    Component.onDestruction: {
        if (root.hasSharedDragState && root.qmlParent.dragIndex === root.itemIndex)
            root.qmlParent.resetDrag();
    }

    onDragReleased: (diffX, diffY) => {
        const velocity = Date.now() - root._lastMoveTime > root.velocityStaleMs ? 0 : root.velocityX;
        root.velocityX = 0;
        root._lastDiffX = 0;
        const fastEnough = Math.abs(velocity) > root.escapeVelocity;
        // Flung back towards where it started: the user changed their mind.
        const thrownBack = fastEnough && (velocity > 0) !== (diffX > 0);
        const farEnough = Math.abs(diffX) > root.dragConfirmThreshold;
        if (diffX !== 0 && !thrownBack && (farEnough || fastEnough))
            root.destroyWithAnimation(diffX < 0, fastEnough ? velocity : 0);
        else
            root.resetDrag();
    }

    ParallelAnimation { // Drag finish animation
        id: destroyAnimation
        property real to: 0
        property bool thrown: false
        property int escapeDuration: root.escapeDurationDefault

        NumberAnimation {
            target: root.target.anchors
            property: "leftMargin"
            to: destroyAnimation.to
            duration: destroyAnimation.escapeDuration
            // Thrown: it keeps the speed it left the finger with. Let go at
            // rest: it accelerates away, an exit (DESIGN 2.5).
            easing.type: destroyAnimation.thrown ? Easing.Linear : Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        }
        NumberAnimation {
            target: root.fadeOnDismiss ? root.owner : null
            property: "opacity"
            to: 0
            duration: destroyAnimation.escapeDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
        onFinished: root.dismissed()
    }
}
