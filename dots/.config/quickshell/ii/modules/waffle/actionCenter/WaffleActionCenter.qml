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

        function onSidebarLeftOpenChanged() {
            if (!GlobalStates.sidebarLeftOpen) {
                content.close();
            }
        }
    }

    PanelWindow {
        id: panelWindow
        visible: GlobalStates.sidebarLeftOpen
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:actionCenter"
        WlrLayershell.keyboardFocus: GlobalStates.sidebarLeftOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            bottom: Config.options.waffles.bar.bottom
            top: !Config.options.waffles.bar.bottom
            right: true
        }

        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        HyprlandFocusGrab {
            id: focusGrab
            active: GlobalStates.sidebarLeftOpen
            windows: [panelWindow]
            onCleared: content.close()
        }

        ActionCenterContent {
            id: content
            anchors.fill: parent

            onClosed: {
                GlobalStates.sidebarLeftOpen = false;
            }
        }
    }

    function toggleOpen() {
        GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle() {
            root.toggleOpen();
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles left sidebar on press"

        onPressed: root.toggleOpen()
    }

    IpcHandler {
        target: "mediaControls"

        function toggle(): void {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }
    }

    GlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }
    }
}
