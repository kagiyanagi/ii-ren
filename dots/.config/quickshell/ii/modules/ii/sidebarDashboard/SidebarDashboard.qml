import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth

    readonly property bool isOnRight: {
        const pos = Config.options.sidebar.position;
        return pos === "default" || pos === "right"; 
    }

    PanelWindow {
        id: panelWindow
        visible: GlobalStates.sidebarRightOpen

        function hide() {
            GlobalStates.sidebarRightOpen = false;
        }

        exclusiveZone: 0
        implicitWidth: sidebarWidth
        WlrLayershell.namespace: root.isOnRight ? "quickshell:sidebarRight" : "quickshell:sidebarLeft"
        WlrLayershell.keyboardFocus: GlobalStates.sidebarRightOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            left: !root.isOnRight
            right: root.isOnRight
            bottom: true
        }

        onVisibleChanged: {
            if (visible) {
                GlobalFocusGrab.addDismissable(panelWindow);
            } else {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                panelWindow.hide();
            }
        }

        Loader {
            id: sidebarContentLoader

            active: GlobalStates.sidebarRightOpen || Config?.options.sidebar.keepRightSidebarLoaded
            sourceComponent: SidebarDashboardContent {}
            
            width: root.sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
            height: parent.height - (Appearance.sizes.hyprlandGapsOut * 2)
            y: Appearance.sizes.hyprlandGapsOut

            focus: GlobalStates.sidebarRightOpen
            
            state: root.isOnRight ? "right" : "left"
            states: [
                State {
                    name: "right"
                    AnchorChanges {
                        target: sidebarContentLoader
                        anchors.right: parent.right
                        anchors.left: undefined
                    }
                    PropertyChanges {
                        target: sidebarContentLoader
                        anchors.rightMargin: Appearance.sizes.hyprlandGapsOut
                        anchors.leftMargin: 0
                    }
                },
                State {
                    name: "left"
                    AnchorChanges {
                        target: sidebarContentLoader
                        anchors.left: parent.left
                        anchors.right: undefined
                    }
                    PropertyChanges {
                        target: sidebarContentLoader
                        anchors.leftMargin: Appearance.sizes.hyprlandGapsOut
                        anchors.rightMargin: 0
                    }
                }
            ]

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    panelWindow.hide();
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarRight"

        function toggle(): void {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }

        function close(): void {
            GlobalStates.sidebarRightOpen = false;
        }

        function open(): void {
            GlobalStates.sidebarRightOpen = true;
        }

        // One of the dashboard's dialogs by name ("Bluetooth", "Wifi", "Hotspot",
        // "NightLight", "ComfortView", "ReadingMode", "AntiFlashbang", "AudioOutput",
        // "AudioInput"), so each is reachable without a pointer — and by scripts,
        // which have none.
        function openDialog(name: string): void {
            GlobalStates.sidebarRightOpen = true;
            const content = sidebarContentLoader.item;
            const key = `show${name}Dialog`;
            if (content && key in content)
                content[key] = true;
        }
    }

    GlobalShortcut {
        name: "sidebarRightToggle"
        description: "Toggles right sidebar on press"
        onPressed: {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }
    }

    GlobalShortcut {
        name: "sidebarRightOpen"
        description: "Opens right sidebar on press"
        onPressed: {
            GlobalStates.sidebarRightOpen = true;
        }
    }

    GlobalShortcut {
        name: "sidebarRightClose"
        description: "Closes right sidebar on press"
        onPressed: {
            GlobalStates.sidebarRightOpen = false;
        }
    }
}