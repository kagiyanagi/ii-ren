pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * System updates service: counts pending updates with whichever of pacman
 * (checkupdates), dnf or emerge the system has.
 */
Singleton {
    id: root

    property bool available: false
    property alias checking: checkUpdatesProc.running
    property int count: 0
    
    readonly property bool updateAdvised: available && count > Config.options.updates.adviseUpdateThreshold
    readonly property bool updateStronglyAdvised: available && count > Config.options.updates.stronglyAdviseUpdateThreshold

    function load() {}
    function refresh() {
        if (!available) return;
        print("[Updates] Checking for system updates")
        checkUpdatesProc.running = true;
    }

    Timer {
        interval: Config.options.updates.checkInterval * 60 * 1000
        repeat: true
        running: Config.ready && Config.options.updates.enableCheck
        onTriggered: {
            print("[Updates] Periodic update check due")
            root.refresh();
        }
    }

    Process {
        id: checkAvailabilityProc
        running: Config.ready && Config.options.updates.enableCheck
        command: ["bash", "-c", "command -v checkupdates || command -v dnf || command -v emerge"]
        onExited: (exitCode, exitStatus) => {
            root.available = (exitCode === 0);
            root.refresh();
        }
    }

    Process {
        id: checkUpdatesProc
        // dnf prints one name/version/repo line per update under a header; emerge
        // one "[ebuild ...]" line per package it would merge.
        command: ["bash", "-c", "if command -v checkupdates >/dev/null; then checkupdates; elif command -v dnf >/dev/null; then dnf -q check-update | awk 'NF==3'; else emerge -puDNq @world 2>/dev/null | grep '^\\['; fi | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.count = parseInt(text.trim());
            }
        }
    }
}
