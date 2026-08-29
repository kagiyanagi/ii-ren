pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * Who is using the microphone, camera, screen and location right now.
 * Microphone comes from Pipewire directly; the rest needs a poll loop
 * (see scripts/privacy/privacystate.sh).
 */
Singleton {
    id: root

    // Nothing here is free, so only watch while the bar widget is placed.
    readonly property bool enabled: {
        const layouts = Config.options.bar.layouts;
        return [layouts.left, layouts.center, layouts.right].some(section => section.some(item => item.id === "privacy_indicator"));
    }

    readonly property bool watchMic: root.enabled && Config.options.bar.indicators.privacy.microphone
    readonly property bool watchCamera: root.enabled && Config.options.bar.indicators.privacy.camera
    readonly property bool watchScreen: root.enabled && Config.options.bar.indicators.privacy.screen
    readonly property bool watchLocation: root.enabled && Config.options.bar.indicators.privacy.location

    // Capture streams. Properties are only filled in for tracked nodes, so
    // filter on what's available untracked and read props after.
    readonly property var micNodes: root.watchMic ? Pipewire.nodes.values.filter(node => node.isStream && !node.isSink && node.audio) : []
    PwObjectTracker {
        objects: root.micNodes
    }

    readonly property var microphoneApps: root.micNodes.reduce((apps, node) => {
        // Until the tracker binds a node its properties are empty, so every
        // filter below would pass and the node would flash up as a microphone.
        if (!node.ready)
            return apps;
        const props = node.properties ?? {};
        // A monitor capture (cava, screen recorders) is not the microphone.
        if (props["stream.capture.sink"])
            return apps;
        const name = props["application.name"] || node.description || node.name;
        if (!name || apps.some(app => app.name === name))
            return apps;
        apps.push({
            name: name,
            process: props["application.process.binary"] || "",
            pid: props["application.process.id"] || 0
        });
        return apps;
    }, [])

    property var cameraApps: []
    property var screenApps: []
    property bool locationInUse: false
    property var locationApps: []

    readonly property var entries: {
        let result = [];
        if (root.watchMic && root.microphoneApps.length > 0)
            result.push({
                kind: "microphone",
                apps: root.microphoneApps
            });
        if (root.watchCamera && root.cameraApps.length > 0)
            result.push({
                kind: "camera",
                apps: root.cameraApps
            });
        if (root.watchScreen && root.screenApps.length > 0)
            result.push({
                kind: "screen",
                apps: root.screenApps
            });
        if (root.watchLocation && root.locationInUse)
            result.push({
                kind: "location",
                apps: root.locationApps
            });
        return result;
    }
    readonly property bool anyInUse: root.entries.length > 0

    Process {
        running: root.watchCamera || root.watchScreen || root.watchLocation
        command: ["bash", Directories.privacyStateScript]
        onRunningChanged: if (!running) {
            root.cameraApps = [];
            root.screenApps = [];
            root.locationInUse = false;
            root.locationApps = [];
        }
        stdout: SplitParser {
            onRead: line => {
                let state;
                try {
                    state = JSON.parse(line);
                } catch (e) {
                    console.warn("PrivacyMonitor: bad state line:", line);
                    return;
                }
                const toApps = list => (list ?? []).map(entry => ({
                            name: entry.name,
                            process: entry.name,
                            pid: entry.pid ?? 0
                        }));
                root.cameraApps = toApps(state.camera);
                root.screenApps = toApps(state.screen);
                root.locationInUse = state.location === true;
                root.locationApps = toApps(state.apps);
            }
        }
    }
}


