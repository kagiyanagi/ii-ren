import Quickshell.Io

/**
 * Persisted geometry and pinning for one floating overlay.
 * Overlays with tabs add `property int tabIndex: 0` at the use site, so the
 * on-disk JSON keeps exactly the keys it had before.
 */
JsonObject {
    property bool pinned: false
    property bool clickthrough: false
    property real x: 0
    property real y: 0
    property real width: 0
    property real height: 0
}
