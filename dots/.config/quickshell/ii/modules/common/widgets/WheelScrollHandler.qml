import QtQuick
import qs.modules.common

/**
 * Faster, accumulating wheel scrolling for a Flickable (or ListView).
 * Wheel deltas stack while the host's scroll animation is still running.
 *
 * The host keeps the `Behavior on contentY` (a Behavior can only be declared
 * on the property's own object), hands its animation over as `scrollAnim`, and
 * calls `syncTarget()` from onContentYChanged.
 */
MouseArea {
    id: handler
    required property Flickable flickable
    // The host's scroll Behavior animation, so deltas can stack mid-flight.
    property Animation scrollAnim

    property real touchpadScrollFactor: Config?.options.interactions.scrolling.touchpadScrollFactor ?? 100
    property real mouseScrollFactor: Config?.options.interactions.scrolling.mouseScrollFactor ?? 50
    property real mouseScrollDeltaThreshold: Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120
    // Accumulated scroll destination so wheel deltas stack while animating
    property real scrollTargetY: 0

    visible: Config?.options.interactions.scrolling.fasterTouchpadScroll
    anchors.fill: parent
    acceptedButtons: Qt.NoButton

    // Keep target synced when not animating (e.g., drag/flick or programmatic changes)
    function syncTarget() {
        if (!handler.scrollAnim?.running) {
            handler.scrollTargetY = handler.flickable.contentY;
        }
    }

    onWheel: function(wheelEvent) {
        const delta = wheelEvent.angleDelta.y / handler.mouseScrollDeltaThreshold;
        // The angleDelta.y of a touchpad is usually small and continuous,
        // while that of a mouse wheel is typically in multiples of ±120.
        var scrollFactor = Math.abs(wheelEvent.angleDelta.y) >= handler.mouseScrollDeltaThreshold ? handler.mouseScrollFactor : handler.touchpadScrollFactor;

        const maxY = Math.max(0, handler.flickable.contentHeight - handler.flickable.height);
        const base = handler.scrollAnim?.running ? handler.scrollTargetY : handler.flickable.contentY;
        var targetY = Math.max(0, Math.min(base - delta * scrollFactor, maxY));

        handler.scrollTargetY = targetY;
        handler.flickable.contentY = targetY;
        wheelEvent.accepted = true;
    }
}
