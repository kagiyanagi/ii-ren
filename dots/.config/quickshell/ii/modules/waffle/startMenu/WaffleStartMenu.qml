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

        function onSearchOpenChanged() {
            if (GlobalStates.searchOpen) {
                panelLoader.active = true;
                LauncherSearch.query = "";
            }
        }

        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked && GlobalStates.searchOpen) {
                GlobalStates.searchOpen = false;
            }
        }
    }

    Loader {
        id: panelLoader
        active: false
        sourceComponent: PanelWindow {
            id: panelWindow
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:wStartMenu"
            WlrLayershell.keyboardFocus: GlobalStates.searchOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            anchors {
                bottom: Config.options.waffles.bar.bottom
                top: !Config.options.waffles.bar.bottom
                left: Config.options.waffles.bar.leftAlignApps
            }

            implicitWidth: content.implicitWidth
            implicitHeight: content.implicitHeight

            HyprlandFocusGrab {
                id: focusGrab
                active: GlobalStates.searchOpen && !GlobalStates.screenLocked
                windows: [panelWindow]
                onCleared: content.close()
            }

            Connections {
                target: GlobalStates
                function onSearchOpenChanged() {
                    if (!GlobalStates.searchOpen) content.close();
                }
            }

            StartMenuContent {
                id: content
                anchors.fill: parent
                focus: true

                onClosed: {
                    GlobalStates.searchOpen = false;
                    panelLoader.active = false;
                    LauncherSearch.query = "";
                }
            }
        }
    }

    function toggleClipboard() {
        if (GlobalStates.searchOpen && LauncherSearch.query.startsWith(Config.options.search.prefix.clipboard)) {
            GlobalStates.searchOpen = false;
            return;
        }
        GlobalStates.searchOpen = true;
        LauncherSearch.ensurePrefix(Config.options.search.prefix.clipboard);
    }

    function toggleEmojis() {
        if (GlobalStates.searchOpen && LauncherSearch.query.startsWith(Config.options.search.prefix.emojis)) {
            GlobalStates.searchOpen = false;
            return;
        }
        GlobalStates.searchOpen = true;
        LauncherSearch.ensurePrefix(Config.options.search.prefix.emojis);
    }

    IpcHandler {
        target: "search"

        function toggle() {
            GlobalStates.searchOpen = !GlobalStates.searchOpen;
        }
        function close() {
            GlobalStates.searchOpen = false;
        }
        function open() {
            GlobalStates.searchOpen = true;
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            GlobalStates.searchOpen = !GlobalStates.searchOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            GlobalStates.searchOpen = !GlobalStates.searchOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }

    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            root.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            root.toggleEmojis();
        }
    }
}
