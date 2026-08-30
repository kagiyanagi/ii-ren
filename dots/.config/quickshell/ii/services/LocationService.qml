pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common

Singleton {
    id: root

    property bool available: false
    property bool enabled: true

    function toggle() {
        const next = !root.enabled;
        maskProc.command = ["bash", Directories.locationServiceScript, next ? "enable" : "disable"];
        maskProc.running = true;
    }

    function refresh() {
        statusProc.running = true;
    }

    Process {
        id: maskProc
        onExited: statusProc.running = true
    }

    Process {
        id: statusProc
        running: true
        command: ["bash", Directories.locationServiceScript, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const state = JSON.parse(text || "{}");
                    root.available = state.present ?? false;
                    root.enabled = state.enabled ?? true;
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: statusProc.running = true
    }
}
