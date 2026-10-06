pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string killDialogQmlPath: FileUtils.trimFileProtocol(Quickshell.shellPath("killDialog.qml"))

    function load() {
        // dummy to force init
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) checkConflictsProc.running = true
        }
    }

    // kded6 is no conflict: the tray host works through its StatusNotifierWatcher.
    // Killing it was the bug -- it segfaults on SIGTERM, KCrash queues a new one
    // that takes the watcher name with no gap, and Quickshell's host keeps every
    // item from before the swap, so each reload added one more copy of every icon.
    Process {
        id: checkConflictsProc
        command: ["pidof", "mako", "dunst"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length === 0) return;
                if (Config.options.conflictKiller.autoKillNotificationDaemons)
                    Quickshell.execDetached(["killall", "mako", "dunst"]);
                else
                    Quickshell.execDetached(["qs", "-p", root.killDialogQmlPath]);
            }
        }
    }
}
