pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Launches the configured apps once per login. Nothing about this is per-shell:
// the config hot-reloads constantly and re-runs Component.onCompleted, so the
// once-only guard is a marker in XDG_RUNTIME_DIR, which the session clears on
// logout but which survives every reload and restart in between.
Singleton {
    id: root

    readonly property string markerPath: `${Quickshell.env("XDG_RUNTIME_DIR") ?? "/tmp"}/quickshell-autostart.done`
    readonly property var apps: Config.options.hyprland.autostartApps.apps ?? []

    property int nextIndex: 0
    property bool running: false

    function load(): void {} // For forcing initialization

    // Runs the list now, ignoring the marker. This is what the settings page's
    // test button calls.
    function launch(): void {
        if (root.running)
            return;
        root.nextIndex = 0;
        root.running = true;
        root.step();
    }

    // One app per tick, then wait out that app's delay before the next. The delay
    // belongs after the launch, so it is the gap the next app waits for.
    function step(): void {
        if (root.nextIndex >= root.apps.length) {
            root.running = false;
            return;
        }
        const app = root.apps[root.nextIndex++];
        const cmd = (app.cmd ?? "").trim();
        if (cmd.length > 0) {
            const workspace = app.workspace ?? 0;
            // "silent" places the window without dragging the current workspace
            // along with it, which is the whole point of autostart.
            const rule = workspace > 0 ? `[workspace ${workspace} silent] ` : "";
            Hyprland.dispatch(`hl.dsp.exec_cmd("${rule}${cmd.replace(/"/g, '\\"')}")`);
        }
        stepTimer.interval = Math.max(0, (app.delay ?? 0) * 1000);
        stepTimer.restart();
    }

    Timer {
        id: stepTimer
        repeat: false
        onTriggered: root.step()
    }

    // set -C makes the redirect fail if the marker already exists, so claiming it
    // is atomic - two shells racing at login cannot both win.
    Process {
        id: claimMarker
        running: false
        command: ["bash", "-c", `set -C; : > "${root.markerPath}"`]
        onExited: exitCode => {
            // Non-zero means the marker was already there: this login has already
            // had its autostart, and this is just another shell reload.
            if (exitCode === 0)
                root.launch();
        }
    }

    // Config arrives in pieces, and its list<var> properties can be mutated in
    // place without emitting a change signal (see the widgetSizesVersion note in
    // AbstractBackgroundWidget), so there is no single edge to hang this on.
    // ponytail: poll for the first 15s of the session instead. Autostart is not
    // latency-sensitive; swap this for a signal if Config ever grows a reliable one.
    property bool claimed: false
    property int attempts: 0

    function claimOnce(): void {
        if (root.claimed || !Config.ready)
            return;
        if (!Config.options.hyprland.autostartApps.enable || root.apps.length === 0)
            return;
        root.claimed = true;
        claimMarker.running = true;
    }

    Timer {
        interval: 1000
        repeat: true
        running: !root.claimed && root.attempts < 15
        onTriggered: {
            root.attempts++;
            root.claimOnce();
        }
    }
}
