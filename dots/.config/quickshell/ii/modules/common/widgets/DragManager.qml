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
    // Losing `interactive` mid-drag -- a notification group collapsing under the
    // finger, a row going non-interactive as the list rebuilds -- used to leave
    // `dragging` true and the last offset standing, because the release below
    // early-returns on exactly that flag and nothing else ever took it back.
    // Treated as a cancelled grab, which snaps back rather than dismissing: the
    // gesture was never finished, so it must not count as a confirmed one.
    onInteractiveChanged: () => {
        if (root.interactive || !root.dragging) {
            return;
        }
        root.dragging = false;
        root.resetDrag();
    }
    onCanceled: () => {
        // `canceled` itself carries no MouseEvent -- re-firing `released` (whose
        // one caller here never reads it) treats a stolen grab like a release.
        if (!root.interactive) {
            return;
        }
        released();
    }
}
