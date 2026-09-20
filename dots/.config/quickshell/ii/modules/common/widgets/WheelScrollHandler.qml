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

    /**
     * One turn of the wheel, as intent rather than as a contentY that moved.
     *
     * `up` is a turn that took the view back toward the start; `toEnd` is one
     * the clamp landed on the very end. A host that follows its end cannot read
     * either off contentY, because its own layout moves contentY too.
     */
    signal scrolled(bool up, bool toEnd)

    // Android-style stretch overscroll. Wheel delta that would land past a bound piles up
    // here instead of being dropped (negative = past the top, positive = past the bottom);
    // the host scales its contentItem by it, and it springs back once the wheel stops.
    property real overscroll: 0
    property real overscrollMax: 0.12   // cap, as a fraction of the viewport height
    property real overscrollFactor: 0.5 // how much of the leftover delta to keep

    // The stretch is a design-law behaviour (3.6), not a scrolling preference, so the
    // handler is always live. `fasterTouchpadScroll` now decides only whether it takes
    // the wheel over; with it off the Flickable scrolls exactly as it always did, and
    // this only picks up what is left once the view is already at a bound.
    // Before: `visible` was bound to that key, and an invisible MouseArea gets no wheel
    // events at all -- so the stretch was dead for everyone on a default config.
    readonly property bool takesOverScroll: Config?.options.interactions.scrolling.fasterTouchpadScroll ?? false
    visible: true
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

    /**
     * Piles leftover travel into the stretch. Negative is past the top, positive past
     * the bottom; the pull diminishes as it fills and springs back when the wheel stops.
     */
    function addOverscroll(excess: real): void {
        const cap = Math.max(1, handler.flickable.height * handler.overscrollMax);
        const room = Math.max(0, 1 - Math.abs(handler.overscroll) / cap); // diminishing pull
        handler.overscroll = Math.max(-cap, Math.min(handler.overscroll + excess * room * handler.overscrollFactor, cap));
        overscrollRelease.restart();
    }

    onWheel: function(wheelEvent) {
        const delta = wheelEvent.angleDelta.y / handler.mouseScrollDeltaThreshold;
        // The angleDelta.y of a touchpad is usually small and continuous,
        // while that of a mouse wheel is typically in multiples of ±120.
        var scrollFactor = Math.abs(wheelEvent.angleDelta.y) >= handler.mouseScrollDeltaThreshold ? handler.mouseScrollFactor : handler.touchpadScrollFactor;

        const maxY = Math.max(0, handler.flickable.contentHeight - handler.flickable.height);

        if (!handler.takesOverScroll) {
            // Not our wheel: hand it back and let Flickable scroll it, which is what
            // every caller got before. The exception is a turn at a bound, where
            // Flickable has nothing left to do and the whole turn is stretch.
            const atBound = (delta > 0 && handler.flickable.atYBeginning) || (delta < 0 && handler.flickable.atYEnd);
            if (!atBound || maxY <= 0) {
                wheelEvent.accepted = false;
                return;
            }
            handler.addOverscroll(-delta * scrollFactor);
            wheelEvent.accepted = true;
            return;
        }
        const base = handler.scrollAnim?.running ? handler.scrollTargetY : handler.flickable.contentY;
        const desiredY = base - delta * scrollFactor;
        var targetY = Math.max(0, Math.min(desiredY, maxY));

        // Whatever the clamp threw away becomes stretch. Skipped when there is nothing to
        // scroll (a horizontal or short list), where an overscroll would make no sense.
        const excess = desiredY - targetY;
        if (excess !== 0 && maxY > 0)
            handler.addOverscroll(excess);

        handler.scrolled(targetY < base, targetY >= maxY);
        handler.scrollTargetY = targetY;
        handler.flickable.contentY = targetY;
        wheelEvent.accepted = true;
    }
}
