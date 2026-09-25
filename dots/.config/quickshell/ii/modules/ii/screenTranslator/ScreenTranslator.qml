pragma ComponentBehavior: Bound
import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root

    function dismiss() {
        GlobalStates.screenTranslatorOpen = false
    }

    readonly property var currentScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null

    // Intent and mapping are kept apart: `active` destroys the window, so bound
    // to the request it would take the fade out with it (DESIGN.md 2.5). The
    // panel releases it once it has faded. A reopen during the fade reverses it
    // on the same panel, whose screenshot and translations are still good.
    Loader {
        id: translatorLoader
        property var lockedScreen
        active: false
        Connections {
            target: GlobalStates
            function onScreenTranslatorOpenChanged() {
                if (!GlobalStates.screenTranslatorOpen || translatorLoader.active)
                    return;
                translatorLoader.lockedScreen = root.currentScreen;
                translatorLoader.active = true;
            }
        }

        sourceComponent: ScreenTranslatorPanel {
            screen: translatorLoader.lockedScreen
            open: GlobalStates.screenTranslatorOpen
            onFadedOut: translatorLoader.active = false
            onDismiss: root.dismiss()
        }
    }

    function translate() {
        GlobalStates.screenTranslatorOpen = true
    }

    IpcHandler {
        target: "screenTranslator"

        function translate() {
            root.translate()
        }
    }

    GlobalShortcut {
        name: "screenTranslate"
        description: "Translates screen content"
        onPressed: root.translate()
    }
}
