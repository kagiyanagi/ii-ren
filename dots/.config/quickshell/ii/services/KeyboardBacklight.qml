pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common.utils

/**
 * Keyboard backlight LED, cycled through its kernel brightness levels.
 */
Singleton {
    id: root

    property string device: ""
    property int maxValue: 0
    property int currentValue: 0
    readonly property bool available: root.device !== "" && root.maxValue > 0

    function cycle(): void {
        if (!root.available) return;
        root.setValue((root.currentValue + 1) % (root.maxValue + 1));
    }

    function setValue(value: int): void {
        if (!root.available) return;
        root.currentValue = value;
        setProc.command = ["brightnessctl", "--class", "leds", "-d", root.device.split("/").pop(), "set", `${value}`];
        setProc.running = true;
    }

    Process {
        running: true
        command: ["bash", "-c", "ls -d /sys/class/leds/*kbd_backlight 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: root.device = text.trim()
        }
    }

    Process {
        id: setProc
    }

    FileView {
        path: root.device ? `${root.device}/max_brightness` : ""
        onLoaded: root.maxValue = parseInt(text().trim(), 10) || 0
    }

    KeepAliveProcess {
        wanted: root.available
        args: ["python3", Quickshell.shellPath("scripts/keyboard-backlight/watch.py"), root.device]
        stdout: SplitParser {
            onRead: data => {
                const value = parseInt(data, 10);
                if (Number.isFinite(value))
                    root.currentValue = Math.max(0, Math.min(root.maxValue, value));
            }
        }
    }
}
