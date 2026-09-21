import qs.modules.common
import QtQuick

/**
 * Swipe a floating card sideways to throw it away. AOSP SwipeHelper, the model
 * NotificationStackView follows: the card goes once it has travelled
 * SWIPED_FAR_ENOUGH_SIZE_FRACTION (0.6) of its own width or been flung past
 * SWIPE_ESCAPE_VELOCITY (500dp/s), and it leaves the way it was pushed, fading
 * as it goes, at the speed it was thrown.
 *
 * Not SwipeDismissible (3.6): that one wants a ListView parent for its
 * neighbour nudging and a flat 70px threshold, and a fraction scales with a
 * card whose width changes.
 *
 * Fills its parent, which is the card body it moves and fades. Compose the
 * offset in rather than writing x, because x usually carries a binding of its
 * own and a Behavior on it would leave the card behind the pointer (2.9):
 *
 *     transform: Translate { x: swipe.offset }
 *     SwipeToDismiss { id: swipe; onDismissed: ... }
 *
 * Do not put that Translate on an item a PanelWindow masks: the mask bakes
 * the transform (check-mask-regions.py). Mask the frame, translate a body
 * inside it.
 *
 * Below the drag threshold the card's buttons keep the grab, so a tap still
 * clicks and only a real drag steals it.
 */
Item {
    id: root
    anchors.fill: parent

    property real offset: 0
    property real velocity: 0
    signal dismissed()

    readonly property real dismissFraction: 0.6
    readonly property real escapeVelocity: 500
    // DEFAULT_ESCAPE_ANIMATION_DURATION / MAX_ESCAPE_ANIMATION_DURATION.
    readonly property int escapeDurationDefault: 200
    readonly property int escapeDurationMax: 400
    // So the card ends fully clear of the corner it leaves.
    readonly property real dismissOvershoot: 20

    // Puts the card back for its next show, or cancels a swipe under way.
    // Leaves opacity alone: a card with an open animation restores that itself.
    function reset(): void {
        escapeAnim.stop();
        root.offset = 0;
    }

    Behavior on offset {
        // Off while the finger is down, or the card lags the drag, and off
        // during the escape so the two do not fight over the write.
        enabled: !dragHandler.active && !escapeAnim.running
        // Fast spatial, the closest this shell has to the spring SwipeHelper
        // snaps back with.
        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
    }

    DragHandler {
        id: dragHandler

        // Nothing to move: the offset is composed in by the caller.
        target: null
        yAxis.enabled: false
        cursorShape: Qt.ClosedHandCursor

        onActiveTranslationChanged: {
            if (!dragHandler.active)
                return;
            root.offset = dragHandler.activeTranslation.x;
            // Latched, because the centroid's velocity is not worth trusting
            // once the press has been released.
            root.velocity = dragHandler.centroid.velocity.x;
        }

        onActiveChanged: {
            if (dragHandler.active)
                return;
            const distance = root.offset;
            const velocity = root.velocity;
            const farEnough = Math.abs(distance) > root.width * root.dismissFraction;
            // A fling only counts if it is going the way the card went.
            const fastEnough = Math.abs(velocity) > root.escapeVelocity && (velocity > 0) === (distance > 0);
            root.velocity = 0;
            if (!farEnough && !fastEnough) {
                root.offset = 0;
                return;
            }
            const goingLeft = fastEnough ? velocity < 0 : distance < 0;
            escapeAnim.to = (root.width + root.dismissOvershoot) * (goingLeft ? -1 : 1);
            // Carry the speed it was thrown at into the way it leaves.
            escapeAnim.escapeDuration = velocity !== 0 ? Math.min(root.escapeDurationMax, Math.abs(escapeAnim.to - distance) * 1000 / Math.abs(velocity)) : root.escapeDurationDefault;
            escapeAnim.restart();
        }
    }

    // A swiped card leaves the way it was pushed. It does not shrink the way a
    // timeout exit does - that one is the card giving up, this is the user
    // throwing it away.
    ParallelAnimation {
        id: escapeAnim

        property real to: 0
        property int escapeDuration: root.escapeDurationDefault

        NumberAnimation {
            target: root
            property: "offset"
            to: escapeAnim.to
            duration: escapeAnim.escapeDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        }
        NumberAnimation {
            target: root.parent
            property: "opacity"
            to: 0
            duration: escapeAnim.escapeDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
        onFinished: root.dismissed()
    }
}
