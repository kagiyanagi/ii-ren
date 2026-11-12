pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common
import qs

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

    // Masking changes only through this toggle or an outside systemctl, so a
    // slow poll is enough for the bar's indicator; the toggle re-reads whenever
    // the dashboard opens. Every 15 s this ran bash and systemctl all day.
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: statusProc.running = true
    }

    Connections {
        target: GlobalStates
        function onDashboardPanelOpenChanged() {
            if (GlobalStates.dashboardPanelOpen) statusProc.running = true;
        }
    }
}
