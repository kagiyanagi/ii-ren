pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: root

    Connections {
        target: GlobalStates

        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) {
                panelLoader.active = true;
            }
        }

        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked && GlobalStates.sidebarRightOpen) {
                GlobalStates.sidebarRightOpen = false;
            }
        }
    }

    Loader {
        id: panelLoader
        active: false
        sourceComponent: PanelWindow {
            id: panelWindow
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:wNotificationCenter"
            WlrLayershell.keyboardFocus: GlobalStates.sidebarRightOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            anchors {
                bottom: true
                top: true
                right: true
            }

            implicitWidth: content.implicitWidth
            implicitHeight: content.implicitHeight

            HyprlandFocusGrab {
                id: focusGrab
                active: GlobalStates.sidebarRightOpen && !GlobalStates.screenLocked
                windows: [panelWindow]
                onCleared: content.close();
            }

            Connections {
                target: GlobalStates
                function onSidebarRightOpenChanged() {
                    if (!GlobalStates.sidebarRightOpen) content.close();
                }
            }

            NotificationCenterContent {
                id: content
                anchors.fill: parent

                onClosed: {
                    GlobalStates.sidebarRightOpen = false;
                    panelLoader.active = false;
                }
            }
        }
    }

    function toggleOpen() {
        if (GlobalStates.sidebarRightOpen) {
            GlobalStates.sidebarRightOpen = false;
        } else {
            GlobalStates.sidebarRightOpen = true;
        }
    }

    IpcHandler {
        target: "sidebarRight"

        function toggle() {
            root.toggleOpen();
        }

        function close() {
            GlobalStates.sidebarRightOpen = false;
        }

        function open() {
            GlobalStates.sidebarRightOpen = true;
        }
    }

    GlobalShortcut {
        name: "sidebarRightToggle"
        description: "Toggles notification center on press"

        onPressed: root.toggleOpen();
    }
}
