pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property bool loaded: false
    property string firstRunFilePath: `${Directories.state}/user/first_run.txt`
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property string firstRunNotifSummary: "Welcome!"
    property string firstRunNotifBody: "Hit Super+/ for a list of keybinds"
    property string defaultWallpaperPath: FileUtils.trimFileProtocol(`${Directories.assetsPath}/images/default_wallpaper.png`)
    property string welcomeQmlPath: FileUtils.trimFileProtocol(Quickshell.shellPath("welcome.qml"))

    function load() {
        if (root.loaded) return;
        root.loaded = true;
        root.ensureWallpaper();
        firstRunFileView.reload();
    }

    function ensureWallpaper() {
        if (!root.loaded || !Config.ready || !Config.options.background.enable
            || Config.options.background.wallpaperPath.trim().length > 0)
            return;

        // The welcome marker can already exist after an interrupted first boot.
        // Set the image through Config after it loads: the switcher's jq write
        // otherwise races the initial config creation and can be lost entirely.
        Config.options.background.wallpaperPath = root.defaultWallpaperPath;
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--image", root.defaultWallpaperPath]);
    }

    function handleFirstRun() {
        Quickshell.execDetached(["qs", "-p", root.welcomeQmlPath]);
    }

    Connections {
        target: Config
        function onReadyChanged() { root.ensureWallpaper(); }
    }

    FileView {
        id: firstRunFileView
        path: Qt.resolvedUrl(firstRunFilePath)
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                firstRunFileView.setText(root.firstRunFileContent)
                root.handleFirstRun()
            }
        }
    }
}
