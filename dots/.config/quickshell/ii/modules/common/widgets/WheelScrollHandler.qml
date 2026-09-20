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

    // `fasterTouchpadScroll` decides whether this handler takes the wheel over; with it
    // off the Flickable scrolls exactly as it always did. The handler stays visible
    // either way and simply hands those turns back -- binding `visible` to the key
    // instead looks equivalent and is not: an invisible MouseArea gets no wheel events
    // at all, so nothing here could ever be reached from a default config.
    readonly property bool takesOverWheel: Config?.options.interactions.scrolling.fasterTouchpadScroll ?? false
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

    onWheel: function(wheelEvent) {
        const delta = wheelEvent.angleDelta.y / handler.mouseScrollDeltaThreshold;
        // The angleDelta.y of a touchpad is usually small and continuous,
        // while that of a mouse wheel is typically in multiples of ±120.
        var scrollFactor = Math.abs(wheelEvent.angleDelta.y) >= handler.mouseScrollDeltaThreshold ? handler.mouseScrollFactor : handler.touchpadScrollFactor;

        const maxY = Math.max(0, handler.flickable.contentHeight - handler.flickable.height);

        if (!handler.takesOverWheel) {
            // Not our wheel: hand it back and let Flickable scroll it, which is what
            // every caller gets on a default config.
            wheelEvent.accepted = false;
            return;
        }
        const base = handler.scrollAnim?.running ? handler.scrollTargetY : handler.flickable.contentY;
        const desiredY = base - delta * scrollFactor;
        var targetY = Math.max(0, Math.min(desiredY, maxY));

        handler.scrolled(targetY < base, targetY >= maxY);
        handler.scrollTargetY = targetY;
        handler.flickable.contentY = targetY;
        wheelEvent.accepted = true;
    }
}
