import QtQuick
import qs.modules.common
import Quickshell.Io

QuickToggleModel {
    id: root
    name: Translation.tr("Location")
    icon: root.toggled ? "location_on" : "location_disabled"
    tooltipText: Translation.tr("GeoClue location service")

    // Only machines that actually have GeoClue get the toggle.
    available: false
    toggled: true

    mainAction: () => {
        root.toggled = !root.toggled;
        maskProc.command = ["bash", Directories.locationServiceScript, root.toggled ? "enable" : "disable"];
        maskProc.running = true;
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
            id: statusCollector
            onStreamFinished: {
                const state = JSON.parse(statusCollector.text || "{}");
                root.available = state.present ?? false;
                root.toggled = state.enabled ?? true;
            }
        }
    }
}
