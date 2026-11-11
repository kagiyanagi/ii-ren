pragma Singleton
pragma ComponentBehavior: Bound

// From https://github.com/caelestia-dots/shell with modifications.
// License: GPLv3

import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.utils
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

/**
 * For managing brightness of monitors. Supports both brightnessctl and ddcutil.
 */
Singleton {
    id: root
    signal brightnessChanged()

    property var ddcMonitors: []
    // One per screen, made and freed with it. A `screens.map(createObject)` binding
    // built a whole new set on every hotplug and left the old ones, processes and
    // all, parented to root.
    readonly property list<BrightnessMonitor> monitors: monitorVariants.instances
    Variants {
        id: monitorVariants
        model: Quickshell.screens
        delegate: BrightnessMonitor {
            required property ShellScreen modelData
            screen: modelData
        }
    }

    // The monitor a brightness gesture means when it comes from something that
    // is not tied to one screen - a keybind, or a slider in a panel that the
    // compositor may have put on either output.
    readonly property var targetScreen: Quickshell.screens.find(screen => screen.name === (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")) || Quickshell.screens[0] || null

    function getMonitorForScreen(screen: ShellScreen): var {
        return monitors.find(m => m.screen === screen);
    }

    function getTargetMonitor(): var {
        return root.getMonitorForScreen(root.targetScreen);
    }

    function increaseBrightness(): void {
        // if gamma is not yet 100, first increase gamma
        if (Hyprsunset.gamma !== 100) {
            Hyprsunset.setGamma(Hyprsunset.gamma + 5);
            return;
        }

        const monitor = root.getTargetMonitor();
        if (monitor?.ready)
            monitor.adjustBrightness(0.05);
    }

    function decreaseBrightness(): void {
        const monitor = root.getTargetMonitor();
        if (!monitor?.ready)
            return;
        monitor.adjustBrightness(-0.05);
    }

    reloadableId: "brightness"

    onMonitorsChanged: {
        ddcMonitors = [];
        ddcProc.refresh();
    }

    function initializeMonitor(i: int): void {
        if (i >= monitors.length)
            return;
        monitors[i].initialize();
    }

    function ddcDetectFinished(): void {
        initializeMonitor(0);
    }

    RefreshProcess {
        id: ddcProc

        command: ["ddcutil", "detect", "--brief"]
        stdout: SplitParser {
            splitMarker: "\n\n"
            onRead: data => {
                if (data.startsWith("Display ")) {
                    const lines = data.split("\n").map(l => l.trim());
                    root.ddcMonitors.push({
                        name: lines.find(l => l.startsWith("DRM connector:")).split("-").slice(1).join('-'),
                        busNum: lines.find(l => l.startsWith("I2C bus:")).split("/dev/i2c-")[1]
                    });
                }
            }
        }
        // FailedToStart changes running back to false without emitting exited.
        // Backlight initialization must happen even when ddcutil is unavailable.
        onRunningChanged: if (!running) root.ddcDetectFinished()
    }

    component BrightnessMonitor: QtObject {
        id: monitor

        required property ShellScreen screen
        property bool isDdc
        property string busNum
        property int rawMaxBrightness: 100
        property real brightness
        property real brightnessMultiplier: 1.0
        property real multipliedBrightness: Math.max(0, Math.min(1, brightness * (Config.options.light.antiFlashbang.enable ? brightnessMultiplier : 1)))
        property bool ready: false
        property bool animateChanges: !monitor.isDdc
        property bool configured: false
        property bool initializing: false
        property bool applyingReading: false
        property int revision: 0
        property int hardwareRaw: -1
        property real pendingAdjustment: 0
        readonly property bool changing: brightnessAnimation.running || setTimer.running || setProc.running || setProc.pendingCommand.length > 0

        onBrightnessChanged: {
            if (!monitor.ready) return;
            root.brightnessChanged();
        }

        Behavior on multipliedBrightness {
            enabled: monitor.animateChanges && monitor.ready && !monitor.applyingReading
            NumberAnimation {
                id: brightnessAnimation
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }
        onMultipliedBrightnessChanged: {
            if (!monitor.ready || monitor.applyingReading)
                return;
            monitor.revision++;
            if (monitor.animateChanges) syncBrightness();
            else setTimer.restart();
        }

        function initialize() {
            monitor.ready = false;
            monitor.initializing = true;
            const match = root.ddcMonitors.find(m => m.name === screen.name && !root.monitors.slice(0, root.monitors.indexOf(this)).some(mon => mon.busNum === m.busNum));
            isDdc = !!match;
            busNum = match?.busNum ?? "";
            initProc.command = isDdc ? ["ddcutil", "-b", busNum, "getvcp", "10", "--brief"] : ["brightnessctl", "--class", "backlight", "-m"];
            monitor.configured = true;
            initProc.refresh();
        }

        function applyReading(data, readRevision) {
            // A read begun before a gesture can finish after it. Never replace
            // the requested value with that older sample or an animation frame.
            if (monitor.changing || readRevision !== monitor.revision)
                return;
            const fields = data.trim().split(monitor.isDdc ? /\s+/ : /,/);
            if (fields.length !== 5 || fields.some(field => field.trim() === ""))
                return;
            const current = Number(fields[monitor.isDdc ? 3 : 2]);
            const max = Number(fields[4]);
            if (!Number.isFinite(current) || !Number.isFinite(max) || max <= 0 || current < 0 || current > max)
                return;
            // Own writes, including anti-flashbang, are already accounted for.
            // Reading their dimmed value must not dim the logical value again.
            if (monitor.ready && current === monitor.hardwareRaw && max === monitor.rawMaxBrightness)
                return;
            monitor.hardwareRaw = current;
            monitor.rawMaxBrightness = max;
            monitor.applyingReading = true;
            monitor.brightness = current / max;
            monitor.ready = true;
            monitor.applyingReading = false;
        }

        function readFinished() {
            if (initProc.running)
                return;
            if (initProc.succeeded)
                monitor.applyReading(brightnessReading.text, initProc.readRevision);
            if (monitor.initializing) {
                monitor.initializing = false;
                root.initializeMonitor(root.monitors.indexOf(monitor) + 1);
            }
            monitor.applyAdjustment();
            monitor.setProc.flush();
        }

        readonly property RefreshProcess initProc: RefreshProcess {
            property int readRevision: 0
            property bool succeeded: false
            stdout: StdioCollector {
                id: brightnessReading
            }
            onRunningChanged: {
                if (running) {
                    readRevision = monitor.revision;
                    succeeded = false;
                } else {
                    // Also advances initialization after FailedToStart. Defer
                    // until the final stdout chunk has been collected.
                    Qt.callLater(monitor.readFinished);
                }
            }
            onExited: (code, status) => { succeeded = code === 0 && status === 0; }
        }

        // Backlight writers (Fn keys, brightnessctl, power daemons) and DDC
        // displays have no shared change signal. DDC reads are deliberately
        // infrequent; a keypress requests a fresh reading between polls too.
        readonly property Timer refreshTimer: Timer {
            interval: monitor.isDdc ? 5000 : 1000
            running: monitor.configured
            repeat: true
            onTriggered: if (!monitor.changing) monitor.initProc.refresh()
        }

        // We need a delay for DDC monitors because they can be quite slow and might act weird with rapid changes
        property var setTimer: Timer {
            id: setTimer
            interval: monitor.isDdc ? 300 : 0
            onTriggered: {
                syncBrightness();
            }
        }

        // Each output owns its writer. Never interrupt a DDC transaction; keep
        // the newest request until this monitor's current write has finished.
        readonly property Process setProc: Process {
            property var pendingCommand: []
            property int pendingRaw: 0
            property int writingRaw: 0

            function submit(args, raw) {
                pendingCommand = args;
                pendingRaw = raw;
                Qt.callLater(flush);
            }

            function flush() {
                if (running || monitor.initProc.running || pendingCommand.length === 0)
                    return;
                command = pendingCommand;
                writingRaw = pendingRaw;
                pendingCommand = [];
                // Until success, a poll must be able to repair a failed write.
                monitor.hardwareRaw = -1;
                running = true;
            }

            onRunningChanged: if (!running) Qt.callLater(flush)
            onExited: (code, status) => {
                if (code === 0 && status === 0)
                    monitor.hardwareRaw = writingRaw;
            }
        }

        function syncBrightness() {
            if (!monitor.ready || monitor.applyingReading)
                return;
            const brightnessValue = Math.max(monitor.multipliedBrightness, 0);
            const rawValueRounded = Math.max(Math.floor(brightnessValue * monitor.rawMaxBrightness), 1);
            if (isDdc) {
                monitor.setProc.submit(["ddcutil", "-b", busNum, "setvcp", "10", rawValueRounded], rawValueRounded);
            } else {
                // Use raw units so readback can recognize our own writes exactly.
                // Keep one hardware step at zero to prevent a fully black screen.
                monitor.setProc.submit(["brightnessctl", "--class", "backlight", "s", rawValueRounded, "--quiet"], rawValueRounded);
            }
        }

        function adjustBrightness(delta: real): void {
            if (!monitor.ready)
                return;
            monitor.pendingAdjustment += delta;
            if (monitor.changing)
                monitor.applyAdjustment();
            else
                monitor.initProc.refresh();
        }

        function applyAdjustment(): void {
            const delta = monitor.pendingAdjustment;
            monitor.pendingAdjustment = 0;
            if (delta === 0 || !monitor.ready)
                return;
            if (delta < 0 && monitor.brightness === 0)
                Hyprsunset.setGamma(Hyprsunset.gamma + delta * 100);
            else
                monitor.setBrightness(monitor.brightness + delta);
        }

        function setBrightness(value: real): void {
            if (!monitor.ready)
                return;
            value = Math.max(0, Math.min(1, value));
            monitor.brightness = value;
        }

        function setBrightnessMultiplier(value: real): void {
            monitor.brightnessMultiplier = value;
        }
    }

    // Anti-flashbang
    property int workspaceAnimationDelay: 500
    property int contentSwitchDelay: 30
    property string screenshotDir: "/tmp/quickshell/brightness/antiflashbang"
    function brightnessMultiplierForLightness(x: real): real {
        // I hand picked some values and fitted an exponential curve for this
        // 6.600135 + 216.360356 * e^(-0.0811129189x)
        // Division by 100 is to normalize to [0, 1]
        return (6.600135 + 216.360356 * Math.pow(Math.E, -0.0811129189 * x)) / 100.0;
    }
    Variants {
        model: Quickshell.screens
        Scope {
            id: screenScope
            required property var modelData
            property string screenName: modelData.name
            property string screenshotPath: `${root.screenshotDir}/screenshot-${screenName}.png`
            Connections {
                enabled: Config.options.light.antiFlashbang.enable && Appearance.m3colors.darkmode
                target: Hyprland
                function onRawEvent(event) {
                    if (["activewindowv2", "windowtitlev2"].includes(event.name)) {
                        screenshotTimer.interval = root.contentSwitchDelay;
                        screenshotTimer.restart();
                    } else if (["workspacev2"].includes(event.name)) {
                        screenshotTimer.interval = root.workspaceAnimationDelay;
                        screenshotTimer.restart();
                    }
                }
            }

            Timer {
                id: screenshotTimer
                interval: 700 // This is what I have for a Hyprland ws anim
                onTriggered: {
                    screenshotProc.running = false;
                    screenshotProc.running = true;
                }
            }

            Process {
                id: screenshotProc
                command: ["bash", "-c",
                    `mkdir -p '${StringUtils.shellSingleQuoteEscape(root.screenshotDir)}'`
                    + ` && grim -o '${StringUtils.shellSingleQuoteEscape(screenScope.screenName)}' -`
                    + ` | magick png:- -colorspace Gray -format "%[fx:mean*100]" info:`
                ]
                stdout: StdioCollector {
                    id: lightnessCollector
                    onStreamFinished: {
                        Quickshell.execDetached(["rm", screenScope.screenshotPath]); // Cleanup
                        const lightness = lightnessCollector.text
                        const newMultiplier = root.brightnessMultiplierForLightness(parseFloat(lightness))
                        Brightness.getMonitorForScreen(screenScope.modelData).setBrightnessMultiplier(newMultiplier)
                    }
                }
            }
        }
    }

    // External trigger points

    IpcHandler {
        target: "brightness"

        function increment() {
            onPressed: root.increaseBrightness()
        }

        function decrement() {
            onPressed: root.decreaseBrightness()
        }
    }

    GlobalShortcut {
        name: "brightnessIncrease"
        description: "Increase brightness"
        onPressed: root.increaseBrightness()
    }

    GlobalShortcut {
        name: "brightnessDecrease"
        description: "Decrease brightness"
        onPressed: root.decreaseBrightness()
    }
}
