pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Fullscreen "now playing" surface: blurred album art behind a now-playing
 * card and a synced-lyrics card. Toggled with `immersiveMedia toggle` or the
 * global shortcut.
 */
Scope {
    id: root

    // The exit animation outlives `immersiveMediaOpen` (DESIGN 2.5), so the
    // window has to stay loaded until the content reports it has left.
    property bool keepLoaded: false

    readonly property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

    function toggle(): void {
        GlobalStates.immersiveMediaOpen = !GlobalStates.immersiveMediaOpen;
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked)
                GlobalStates.immersiveMediaOpen = false;
        }
        function onImmersiveMediaOpenChanged() {
            if (GlobalStates.immersiveMediaOpen) {
                root.keepLoaded = true;
                unloadFallback.stop();
            } else {
                unloadFallback.restart();
            }
        }
    }

    // A fullscreen surface holding an exclusive keyboard grab must never get
    // stuck loaded if the exit transition is skipped, so tear it down anyway.
    Timer {
        id: unloadFallback
        interval: Appearance.animation.elementMoveEnter.duration
        onTriggered: root.keepLoaded = false
    }

    Loader {
        id: immersiveLoader
        active: GlobalStates.immersiveMediaOpen || root.keepLoaded

        sourceComponent: PanelWindow {
            id: immersiveWindow
            visible: immersiveLoader.active
            screen: root.focusedScreen

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:immersiveMedia"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            ImmersiveMediaContent {
                id: content
                anchors.fill: parent
                focus: true
                shown: GlobalStates.immersiveMediaOpen
                onRequestClose: GlobalStates.immersiveMediaOpen = false
                onClosed: {
                    unloadFallback.stop();
                    root.keepLoaded = false;
                }
            }
        }
    }

    IpcHandler {
        target: "immersiveMedia"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            GlobalStates.immersiveMediaOpen = true;
        }

        function close(): void {
            GlobalStates.immersiveMediaOpen = false;
        }
    }

    GlobalShortcut {
        name: "immersiveMediaToggle"
        description: "Toggles the fullscreen media player"

        onPressed: root.toggle()
    }
    GlobalShortcut {
        name: "immersiveMediaOpen"
        description: "Opens the fullscreen media player"

        onPressed: GlobalStates.immersiveMediaOpen = true
    }
    GlobalShortcut {
        name: "immersiveMediaClose"
        description: "Closes the fullscreen media player"

        onPressed: GlobalStates.immersiveMediaOpen = false
    }
}
