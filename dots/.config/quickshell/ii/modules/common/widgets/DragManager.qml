import QtQuick

/**
 * A convenience MouseArea for handling drag events.
 */
MouseArea {
    id: root
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton

    property bool interactive: true
    property bool automaticallyReset: true
    readonly property real dragDiffX: _dragDiffX
    readonly property real dragDiffY: _dragDiffY
    property real startX: 0
    property real startY: 0
    property real regionTopLeftX: Math.min(startX, startX + _dragDiffX)
    property real regionTopLeftY: Math.min(startY, startY + _dragDiffY)
    property real regionWidth: Math.abs(_dragDiffX)
    property real regionHeight: Math.abs(_dragDiffY)

    signal dragPressed(diffX: real, diffY: real)
    signal dragReleased(diffX: real, diffY: real)
    
    property bool dragging: false
    property real _dragDiffX: 0
    property real _dragDiffY: 0

    function resetDrag() {
        _dragDiffX = 0
        _dragDiffY = 0
    }

    onPressed: (mouse) => {
        if (!root.interactive) {
            if (mouse.button === Qt.LeftButton) {
                mouse.accepted = false;
            }
            return;
        }
        if (mouse.button === Qt.LeftButton) {
            startX = mouse.x
            startY = mouse.y
        }
    }
    onReleased: (mouse) => {
        if (!root.interactive) {
            return;
        }
        dragging = false
        root.dragReleased(_dragDiffX, _dragDiffY);
        if (root.automaticallyReset) {
            root.resetDrag();
        }
    }
    onPositionChanged: (mouse) => {
        if (!root.interactive) {
            return;
        }
        if (mouse.buttons & Qt.LeftButton) {
            root._dragDiffX = mouse.x - startX
            root._dragDiffY = mouse.y - startY
            const dist = Math.sqrt(root._dragDiffX * root._dragDiffX + root._dragDiffY * root._dragDiffY);
            root.dragPressed(_dragDiffX, _dragDiffY);
            root.dragging = true;
        }
    }
    /**
     * A drag that stopped without a release. Two ways in, and the release above
     * reaches neither: the row loses `interactive` mid-gesture -- a notification
     * group collapsing under the finger -- and `onReleased` early-returns on
     * exactly that flag; or the grab is taken away, which is what a wheel turn
     * during a swipe does, and what a Flickable does when it starts scrolling
     * under one. Either way `dragging` stayed true, which is what callers gate
     * their snap-back Behavior on, and the last offset stood: the row sat where
     * the finger left it for as long as it lived.
     *
     * Neither is a finished gesture, so both snap back and neither dismisses.
     * `dragging` is cleared first, or the offset is taken away while the
     * Behavior is still switched off and the row jumps home with no animation.
     */
    function cancelDrag(): void {
        if (!root.dragging) {
            return;
        }
        root.dragging = false;
        root.resetDrag();
    }

    onInteractiveChanged: () => {
        if (!root.interactive)
            root.cancelDrag();
    }
    // Not `released()`: `canceled` carries no MouseEvent, and emitting the
    // one-argument signal with no argument threw "Insufficient arguments" on
    // every cancelled grab, so nothing after that line ever ran.
    onCanceled: () => root.cancelDrag()
}
