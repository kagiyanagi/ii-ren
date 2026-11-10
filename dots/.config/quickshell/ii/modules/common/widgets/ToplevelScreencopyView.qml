import QtQuick
import Quickshell.Wayland

/**
 * A ScreencopyView of one window that comes back after a failed frame.
 *
 * Hyprland fails a window frame whose buffer no longer fits the window, so a
 * resize between the request and the copy fails it, and so does every frame of
 * a re-tile: one probe saw 400-500ms of failures per re-tile, the length of the
 * resize animation. Quickshell's ScreencopyView answers the first failure by
 * dropping its capture context, and it makes a new one only when
 * `captureSource` changes to a different object. The overview keeps its window
 * delegates for the whole session, so one re-tile left that window's preview
 * blank until the shell restarted.
 *
 * Set `toplevel`, not `captureSource`. While there is no frame and `retry`
 * holds, the source is re-armed (a fresh context for the same window) at once
 * and then every `retryInterval` until a frame lands. Bind `retry` to whether
 * the view is on screen: a window that cannot be captured then costs one
 * request per interval while it is shown and none after.
 */
ScreencopyView {
    id: root

    /** The window to show: a Quickshell toplevel, or null for none. */
    property var toplevel
    /** Keep re-arming a capture that failed. Bind it to whether the view is shown. */
    property bool retry: visible
    // Not motion: how often a failed capture is tried again. Under the measured
    // re-tile, so a preview is back within this long of its window settling,
    // and two or three failed attempts per re-tile at most.
    property int retryInterval: 250

    property bool armed: true
    captureSource: armed ? toplevel : null

    function rearm(): void {
        armed = false;
        armed = true;
    }

    Timer {
        running: root.retry && !!root.toplevel && !root.hasContent
        interval: root.retryInterval
        repeat: true
        // At once when it starts: on open, a capture that failed while the view
        // was hidden comes back on the next frame rather than an interval later.
        triggeredOnStart: true
        onTriggered: root.rearm()
    }
}
