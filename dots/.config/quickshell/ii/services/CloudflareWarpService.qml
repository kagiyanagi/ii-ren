pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property bool available: false
    property bool connected: false

    function toggle() {
        if (!available) {
            Quickshell.execDetached(["notify-send",
                "Cloudflare WARP",
                "Daemon is not running. Start it with: sudo systemctl enable --now warp-svc",
                "-a", "Shell"
            ]);
            return;
        }
        const willConnect = !root.connected;
        root.connected = willConnect;
        actionProc.command = ["warp-cli", willConnect ? "connect" : "disconnect"];
        actionProc.running = true;
    }

    function refresh() {
        fetchActiveState.running = true;
    }

    Process {
        id: actionProc
        onExited: (exitCode, exitStatus) => {
            fetchActiveState.running = true;
            fastCheckTimer.restart();
        }
    }

    Timer {
        id: fastCheckTimer
        interval: 600
        onTriggered: fetchActiveState.running = true
    }

    Process {
        id: fetchActiveState
        running: true
        command: ["bash", "-c", "warp-cli status 2>&1"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.includes("Connected")) {
                    root.available = true;
                    root.connected = true;
                } else if (text.includes("Disconnected") || text.includes("Success")) {
                    root.available = true;
                    root.connected = false;
                } else {
                    root.available = false;
                    root.connected = false;
                }
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: 3000
        running: true
        repeat: true
        onTriggered: fetchActiveState.running = true
    }
}
