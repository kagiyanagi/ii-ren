pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * Service managing system app and folder icon themes (Dolphin, GTK, Qt).
 * Coordinates dynamic Material You recolorable icon packs (FollowsColorScheme=true)
 * with light and dark mode switching.
 */
Singleton {
    id: root

    property var availableThemes: []
    property var dynamicThemes: []
    property string currentSystemTheme: ""
    property bool isCurrentDynamic: false

    readonly property string listScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/icons/list-icon-themes.py`)
    readonly property string applyScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/colors/apply-icon-theme.sh`)

    property string lightTheme: Config.options?.appearance?.icons?.lightTheme ?? "breeze-plus"
    property string darkTheme: Config.options?.appearance?.icons?.darkTheme ?? "breeze-plus-dark"
    property bool autoSwitchWithDarkMode: Config.options?.appearance?.icons?.autoSwitchWithDarkMode ?? true
    property bool enableThemed: Config.options?.appearance?.icons?.enableThemed ?? true

    onLightThemeChanged: {
        if (Config?.options?.appearance?.icons && Config.options.appearance.icons.lightTheme !== root.lightTheme) {
            Config.options.appearance.icons.lightTheme = root.lightTheme;
        }
    }

    onDarkThemeChanged: {
        if (Config?.options?.appearance?.icons && Config.options.appearance.icons.darkTheme !== root.darkTheme) {
            Config.options.appearance.icons.darkTheme = root.darkTheme;
        }
    }

    onAutoSwitchWithDarkModeChanged: {
        if (Config?.options?.appearance?.icons && Config.options.appearance.icons.autoSwitchWithDarkMode !== root.autoSwitchWithDarkMode) {
            Config.options.appearance.icons.autoSwitchWithDarkMode = root.autoSwitchWithDarkMode;
        }
    }

    function refreshThemes() {
        listThemesProc.running = true;
        checkCurrentThemeProc.running = true;
    }

    function setThemed(enabled) {
        root.enableThemed = enabled;
        if (Config?.options?.appearance?.icons) {
            Config.options.appearance.icons.enableThemed = enabled;
        }
        if (enabled) {
            root.applyTheme(Appearance.m3colors.darkmode);
        }
    }

    function applyTheme(isDark, themeOverride) {
        const mode = isDark ? "dark" : "light";
        const args = [root.applyScriptPath, "--light", root.lightTheme, "--dark", root.darkTheme, "--mode", mode];
        if (themeOverride && themeOverride.length > 0) {
            args.push("--theme", themeOverride);
        }
        Quickshell.execDetached(args);
        
        // Refresh local state after applying
        refreshStateTimer.restart();
    }

    function applyCurrent() {
        root.applyTheme(Appearance.m3colors.darkmode);
    }

    Process {
        id: listThemesProc
        command: ["python", root.listScriptPath]
        stdout: SplitParser {
            splitMarker: ""
            onRead: (data) => {
                try {
                    const parsed = JSON.parse(data.trim());
                    if (Array.isArray(parsed)) {
                        root.availableThemes = parsed;
                        root.dynamicThemes = parsed.filter(t => t.dynamic);
                        root.updateIsCurrentDynamic();
                    }
                } catch (e) {
                    console.warn("[IconThemes] Failed to parse icon themes JSON:", e);
                }
            }
        }
    }

    Process {
        id: checkCurrentThemeProc
        command: ["bash", "-c", "kreadconfig6 --file kdeglobals --group Icons --key Theme 2>/dev/null || gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d \"'\""]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (data) => {
                const theme = data.trim();
                if (theme.length > 0) {
                    root.currentSystemTheme = theme;
                    root.updateIsCurrentDynamic();
                }
            }
        }
    }

    function updateIsCurrentDynamic() {
        if (!root.currentSystemTheme) return;
        if (root.currentSystemTheme.endsWith("-Dynamic")) {
            root.isCurrentDynamic = true;
            return;
        }
        if (root.availableThemes.length === 0) return;
        const matched = root.availableThemes.find(t => t.id === root.currentSystemTheme);
        root.isCurrentDynamic = matched ? matched.dynamic : false;
    }

    Timer {
        id: refreshStateTimer
        interval: 400
        repeat: false
        onTriggered: {
            checkCurrentThemeProc.running = true;
        }
    }

    // Auto-switch icon pack when system dark mode changes
    Connections {
        target: Appearance.m3colors
        function onDarkmodeChanged() {
            if (root.autoSwitchWithDarkMode && root.enableThemed) {
                root.applyTheme(Appearance.m3colors.darkmode);
            }
        }
    }

    Component.onCompleted: {
        root.refreshThemes();
    }
}
