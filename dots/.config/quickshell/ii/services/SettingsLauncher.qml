pragma Singleton
import Quickshell

Singleton {
    function open(page = "", highlight = "") {
        const window = HyprlandData.windowList.filter(window => window.title === "illogical-impulse Settings")
            .sort((a, b) => a.focusHistoryID - b.focusHistoryID)[0];
        if (window && !FloatingMode.restoreMinimized(window.address))
            FloatingMode.focus(window.address);
        Quickshell.execDetached(["python3", Quickshell.shellPath("scripts/settings/open.py"),
            Quickshell.shellPath("settings.qml"), page, highlight]);
    }
}
