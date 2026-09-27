pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope

    Variants {
        id: overviewVariants
        model: Quickshell.screens

        Loader {
            id: panelLoader
            required property var modelData
            property bool shouldBeActive: false
            active: shouldBeActive

            Connections {
                target: GlobalStates
                function onOverviewOpenChanged() {
                    if (GlobalStates.overviewOpen && !GlobalStates.screenLocked) {
                        panelLoader.shouldBeActive = true;
                    }
                }
                function onScreenLockedChanged() {
                    if (GlobalStates.screenLocked && GlobalStates.overviewOpen) {
                        GlobalStates.overviewOpen = false;
                    }
                }
            }

            sourceComponent: PanelWindow {
                id: root
                readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
                readonly property bool monitorIsFocused: Boolean(Hyprland.focusedMonitor && monitor && Hyprland.focusedMonitor.id === monitor.id)
                screen: panelLoader.modelData

                WlrLayershell.namespace: "quickshell:wTaskView"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: (GlobalStates.overviewOpen && !GlobalStates.screenLocked) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
                color: "transparent"

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                HyprlandFocusGrab {
                    id: focusGrab
                    active: GlobalStates.overviewOpen && root.monitorIsFocused
                    windows: [root]
                    onCleared: {
                        if (active) {
                            GlobalStates.overviewOpen = false;
                        }
                    }
                }

                TaskViewContent {
                    id: taskViewContent
                    anchors.fill: parent

                    Component.onCompleted: {
                        taskViewContent.forceActiveFocus();
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            GlobalStates.overviewOpen = false;
                        }
                    }

                    Connections {
                        target: GlobalStates
                        function onOverviewOpenChanged() {
                            if (GlobalStates.overviewOpen) {
                                taskViewContent.open();
                            } else {
                                taskViewContent.close();
                            }
                        }
                    }
                    onClosed: panelLoader.shouldBeActive = false
                }
            }
        }
    }

    IpcHandler {
        target: "taskView"

        function toggle() {
            if (GlobalStates.screenLocked) return;
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            if (GlobalStates.screenLocked) return;
            GlobalStates.overviewOpen = true;
        }
        function workspacesToggle() {
            toggle();
        }
    }

    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            if (GlobalStates.screenLocked) return;
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
}
