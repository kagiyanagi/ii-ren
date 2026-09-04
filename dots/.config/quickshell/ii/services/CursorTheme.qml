pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * Service managing system cursor theme and size (Hyprland, GTK, Qt/KDE).
 */
Singleton {
    id: root

    property var availableThemes: []
    property string currentSystemTheme: ""
    property int currentSystemSize: 24

    readonly property string listScriptPath: Directories.listCursorScriptPath
    readonly property string queryScriptPath: Directories.queryCursorScriptPath
    readonly property string applyScriptPath: Directories.applyCursorScriptPath

    property string configuredTheme: Config.options?.appearance?.cursor?.theme ?? "Bibata-Modern-Classic"
    property int configuredSize: Config.options?.appearance?.cursor?.size ?? 24

    readonly property var currentThemeDetails: {
        for (let i = 0; i < root.availableThemes.length; i++) {
            if (root.availableThemes[i].id === root.configuredTheme) {
                return root.availableThemes[i];
            }
        }
        return null;
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready && Config.options?.appearance?.cursor) {
                if (Config.options.appearance.cursor.theme) {
                    root.configuredTheme = Config.options.appearance.cursor.theme;
                }
                if (Config.options.appearance.cursor.size) {
                    root.configuredSize = Config.options.appearance.cursor.size;
                }
            }
        }
    }

    onConfiguredThemeChanged: {
        if (Config.ready && Config?.options?.appearance?.cursor && Config.options.appearance.cursor.theme !== root.configuredTheme) {
            Config.options.appearance.cursor.theme = root.configuredTheme;
        }
    }

    onConfiguredSizeChanged: {
        if (Config.ready && Config?.options?.appearance?.cursor && Config.options.appearance.cursor.size !== root.configuredSize) {
            Config.options.appearance.cursor.size = root.configuredSize;
        }
    }

    function refreshThemes() {
        listThemesProc.running = true;
        checkCurrentThemeProc.running = true;
    }

    function setCursor(theme, size) {
        if (theme && theme.length > 0) {
            root.configuredTheme = theme;
            if (Config.ready && Config?.options?.appearance?.cursor) {
                Config.options.appearance.cursor.theme = theme;
            }
        }
        if (size && size > 0) {
            root.configuredSize = size;
            if (Config.ready && Config?.options?.appearance?.cursor) {
                Config.options.appearance.cursor.size = size;
            }
        }
        root.applyCursor(root.configuredTheme, root.configuredSize);
    }

    function applyCursor(theme, size) {
        const t = theme || root.configuredTheme;
        const s = size || root.configuredSize;
        Quickshell.execDetached([root.applyScriptPath, "--theme", t, "--size", String(s)]);
        refreshTimer.restart();
    }

    function applyCurrent() {
        root.applyCursor(root.configuredTheme, root.configuredSize);
    }

    Process {
        id: listThemesProc
        command: ["python3", root.listScriptPath]
        stdout: SplitParser {
            splitMarker: ""
            onRead: (data) => {
                try {
                    const parsed = JSON.parse(data.trim());
                    if (Array.isArray(parsed)) {
                        root.availableThemes = parsed;
                    }
                } catch (e) {
                    console.warn("[CursorTheme] Failed to parse cursor themes JSON:", e);
                }
            }
        }
    }

    Process {
        id: checkCurrentThemeProc
        command: ["python3", root.queryScriptPath]
        stdout: SplitParser {
            splitMarker: ""
            onRead: (data) => {
                try {
                    const parsed = JSON.parse(data.trim());
                    if (parsed && typeof parsed === "object") {
                        if (parsed.theme && parsed.theme.length > 0) {
                            root.currentSystemTheme = parsed.theme;
                        }
                        if (parsed.size && typeof parsed.size === "number" && parsed.size > 0) {
                            root.currentSystemSize = parsed.size;
                        }
                    }
                } catch (e) {
                    console.warn("[CursorTheme] Failed to parse current cursor status JSON:", e);
                }
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: 500
        repeat: false
        onTriggered: {
            checkCurrentThemeProc.running = true;
        }
    }

    Component.onCompleted: {
        root.refreshThemes();
    }
}
