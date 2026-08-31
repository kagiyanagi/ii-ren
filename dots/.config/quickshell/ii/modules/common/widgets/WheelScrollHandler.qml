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

    // Android-style stretch overscroll. Wheel delta that would land past a bound piles up
    // here instead of being dropped (negative = past the top, positive = past the bottom);
    // the host scales its contentItem by it, and it springs back once the wheel stops.
    property real overscroll: 0
    property real overscrollMax: 0.12   // cap, as a fraction of the viewport height
    property real overscrollFactor: 0.5 // how much of the leftover delta to keep

    visible: Config?.options.interactions.scrolling.fasterTouchpadScroll
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    // Behind the content, not over it. Every MouseArea registers an ArrowCursor
    // in its constructor whether or not cursorShape is set, and Qt resolves the
    // pointer shape from the topmost cursor-bearing item -- so at z 0 this sheet
    // overrode every pointing hand and I-beam in the list it scrolls. Wheel
    // events still arrive: delivery tries everything under the point until one
    // accepts, and the content above never accepts a wheel.
    z: -1

    // Keep target synced when not animating (e.g., drag/flick or programmatic changes)
    function syncTarget() {
        if (!handler.scrollAnim?.running) {
            handler.scrollTargetY = handler.flickable.contentY;
        }
    }

    Behavior on overscroll {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    Timer {
        id: overscrollRelease
        interval: 60
        onTriggered: handler.overscroll = 0
    }

    onWheel: function(wheelEvent) {
        const delta = wheelEvent.angleDelta.y / handler.mouseScrollDeltaThreshold;
        // The angleDelta.y of a touchpad is usually small and continuous,
        // while that of a mouse wheel is typically in multiples of ±120.
        var scrollFactor = Math.abs(wheelEvent.angleDelta.y) >= handler.mouseScrollDeltaThreshold ? handler.mouseScrollFactor : handler.touchpadScrollFactor;

        const maxY = Math.max(0, handler.flickable.contentHeight - handler.flickable.height);
        const base = handler.scrollAnim?.running ? handler.scrollTargetY : handler.flickable.contentY;
        const desiredY = base - delta * scrollFactor;
        var targetY = Math.max(0, Math.min(desiredY, maxY));

        // Whatever the clamp threw away becomes stretch. Skipped when there is nothing to
        // scroll (a horizontal or short list), where an overscroll would make no sense.
        const excess = desiredY - targetY;
        if (excess !== 0 && maxY > 0) {
            const cap = Math.max(1, handler.flickable.height * handler.overscrollMax);
            const room = Math.max(0, 1 - Math.abs(handler.overscroll) / cap); // diminishing pull
            handler.overscroll = Math.max(-cap, Math.min(handler.overscroll + excess * room * handler.overscrollFactor, cap));
            overscrollRelease.restart();
        }

        handler.scrollTargetY = targetY;
        handler.flickable.contentY = targetY;
        wheelEvent.accepted = true;
    }
}
