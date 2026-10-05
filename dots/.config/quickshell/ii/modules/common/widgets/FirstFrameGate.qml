import QtQuick

/**
 * Holds a popup's open until its window can show every frame of it.
 *
 * A popup's first visible frame is the first time Qt renders its content in that
 * window, and it cost 50-110ms on the dock menu and the bar popups (measured
 * 2026-10-05). With this many windows the animation clock is wall time, so the
 * open jumped that far ahead: the first frames repeated one early state and the
 * grow resumed 40% of the way in. So that frame is paid for while nothing shows:
 *
 *  - the caller puts its surface at `warmOpacity` and calls `hold()`. Qt still
 *    draws a subtree that faint (QSGOpacityNode culls below 0.001), but under
 *    1/255 none of it reaches the screen;
 *  - `ready` fires once two of the window's frames land under 34ms - two 60Hz
 *    frames - apart, which a frame that blocked cannot;
 *  - the caller starts its open from its resting state there. A window that is
 *    already drawing gets there in a frame or two.
 */
QtObject {
    id: root

    /** Any item in the popup's window. */
    property Item item: null
    readonly property real warmOpacity: 0.002

    signal ready

    property real _lastFrame: -1 // 0 before a hold's first frame, -1 when nothing is held

    function hold(): void {
        root._lastFrame = 0;
        root.item?.Window.window?.update();
    }

    function cancel(): void {
        root._lastFrame = -1;
    }

    // afterAnimating is the GUI thread's; frameSwapped and the rendering signals
    // come from the render thread, where no JS may run.
    readonly property Connections _frames: Connections {
        target: root._lastFrame >= 0 ? (root.item?.Window.window ?? null) : null
        function onAfterAnimating() {
            if (root._lastFrame < 0)
                return;
            const now = Date.now();
            if (root._lastFrame === 0 || now - root._lastFrame >= 34) {
                root._lastFrame = now;
                root.item.Window.window.update();
                return;
            }
            root._lastFrame = -1;
            root.ready();
        }
    }
}
