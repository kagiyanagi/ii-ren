pragma Singleton

import QtQuick
import qs.modules.common
import qs.modules.common.utils
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Simple hyprsunset service with automatic mode.
 * Starts the daemon if needed and retries IPC until its socket is ready.
 */
Singleton {
    id: root
    signal gammaChangeAttempt()

    readonly property real gammaLowerLimit: 25

    property string from: Config.options?.light?.night?.from ?? "19:00" 
    property string to: Config.options?.light?.night?.to ?? "06:30"
    property bool automatic: Config.options?.light?.night?.automatic && (Config?.ready ?? true)
    property int colorTemperature: Config.options?.light?.night?.colorTemperature ?? 5000
    property int defaultColorTemperature: 6000
    property int gamma: 100
    property bool shouldBeOn
    property bool firstEvaluation: true
    property bool temperatureActive: false
    property int requestedTemperature: defaultColorTemperature
    property int temperatureRevision: 0
    property bool temperaturePending: false

    property int fromHour: Number(from.split(":")[0])
    property int fromMinute: Number(from.split(":")[1])
    property int toHour: Number(to.split(":")[0])
    property int toMinute: Number(to.split(":")[1])

    property int clockHour: DateTime.clock.hours
    property int clockMinute: DateTime.clock.minutes

    property var manualActive
    property int manualActiveHour
    property int manualActiveMinute

    onClockMinuteChanged: reEvaluate()
    onAutomaticChanged: {
        root.manualActive = undefined;
        root.firstEvaluation = true;
        reEvaluate();
    }

    function inBetween(t, from, to) {
        if (from < to) {
            return (t >= from && t <= to);
        } else {
            // Wrapped around midnight
            return (t >= from || t <= to);
        }
    }

    function reEvaluate() {
        const t = clockHour * 60 + clockMinute;
        const from = fromHour * 60 + fromMinute;
        const to = toHour * 60 + toMinute;
        const manualActive = manualActiveHour * 60 + manualActiveMinute;

        if (root.manualActive !== undefined && (inBetween(from, manualActive, t) || inBetween(to, manualActive, t))) {
            root.manualActive = undefined;
        }
        root.shouldBeOn = inBetween(t, from, to);
        if (firstEvaluation) {
            firstEvaluation = false;
            root.ensureState();
        }
    }

    onShouldBeOnChanged: ensureState()
    function ensureState() {
        // console.log("[Hyprsunset] Ensuring state:", root.shouldBeOn, "Automatic mode:", root.automatic);
        if (!root.automatic || root.manualActive !== undefined)
            return;
        if (root.shouldBeOn) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    function startHyprsunset() {
        Quickshell.execDetached(["bash", "-c", `pidof hyprsunset || hyprsunset`]);
    }

    function load() {
        root.startHyprsunset();
        root.ensureState();
        root.fetchState();
    }

    Timer {
        id: updateHyprsunset
        interval: 500
        repeat: false
        onTriggered: {
            root.startHyprsunset();
            if (root.temperaturePending) temperatureProc.refresh();
        }
    }

    function enableTemperature() {
        root.applyTemperature(root.colorTemperature);
    }

    function disableTemperature() {
        root.applyTemperature(root.defaultColorTemperature);
    }

    function applyTemperature(temperature) {
        root.requestedTemperature = temperature;
        root.temperatureRevision++;
        root.temperaturePending = true;
        root.startHyprsunset();
        temperatureProc.refresh();
    }

    function retryTemperature() {
        if (root.temperaturePending && !temperatureProc.running)
            updateHyprsunset.restart();
    }

    RefreshProcess {
        id: temperatureProc
        property int applyingRevision: 0
        property int applyingTemperature: 0
        command: ["hyprctl", "hyprsunset", "temperature", `${root.requestedTemperature}`]
        onRunningChanged: {
            if (running) {
                applyingRevision = root.temperatureRevision;
                applyingTemperature = root.requestedTemperature;
            } else {
                // FailedToStart has no exited signal. Defer until onExited has
                // acknowledged success before deciding whether to retry.
                Qt.callLater(root.retryTemperature);
            }
        }
        onExited: (code, status) => {
            if (code !== 0 || status !== 0 || applyingRevision !== root.temperatureRevision) return;
            root.temperaturePending = false;
            root.temperatureActive = applyingTemperature !== root.defaultColorTemperature;
            updateHyprsunset.stop();
        }
    }

    function setGamma(gamma) {
        root.gamma = Math.max(root.gammaLowerLimit, Math.min(100, gamma));

        root.gammaChangeAttempt();

        root.startHyprsunset();
        Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset gamma ${root.gamma}`]);
    }

    function fetchState() {
        fetchProc.refresh();
    }

    RefreshProcess {
        id: fetchProc
        running: true
        property int readRevision: 0
        property bool readingPending: false
        command: ["hyprctl", "hyprsunset", "temperature"]
        onRunningChanged: if (running) {
            readRevision = root.temperatureRevision;
            readingPending = root.temperaturePending;
        }
        stdout: StdioCollector {
            id: stateCollector
        }
        onExited: (code, status) => {
            const output = stateCollector.text.trim();
            if (code !== 0 || status !== 0 || !/^\d+$/.test(output)
                || readingPending || root.temperaturePending || readRevision !== root.temperatureRevision) return;
            root.temperatureActive = Number(output) !== root.defaultColorTemperature;
        }
    }

    function toggleTemperature(active = undefined) {
        if (root.manualActive === undefined) {
            root.manualActive = root.temperatureActive;
            root.manualActiveHour = root.clockHour;
            root.manualActiveMinute = root.clockMinute;
        }

        root.manualActive = active !== undefined ? active : !root.manualActive;
        if (root.manualActive) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    // Change temp
    Connections {
        target: Config.options.light.night
        function onColorTemperatureChanged() {
            if (root.temperaturePending ? root.requestedTemperature === root.defaultColorTemperature : !root.temperatureActive) return;
            root.applyTemperature(Config.options.light.night.colorTemperature);
        }
    }
}
