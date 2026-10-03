import QtQuick
import Quickshell.Io

/**
 * A Process for a helper that should run for as long as `wanted`: started and stopped
 * with it, and started again if it exits on its own. A plain `running: <binding>`
 * stays false after a crash - the binding has nothing new to say - and the feature
 * behind it is dead until the next shell restart.
 *
 * Waits 1s before the first restart and doubles to a minute, so a helper that dies
 * at once costs one exec a minute rather than a spin. A minute of uptime resets it.
 *
 * Set `args`, not `command`: the helper is started under setpriv --pdeathsig, so it
 * goes when the shell does. A killed or crashed shell runs no destructors, and every
 * `pkill qs` used to leave another nmcli/gdbus monitor running for the session.
 */
Process {
    id: root

    property bool wanted: true
    required property list<string> args
    property int _wait: 1000

    command: ["setpriv", "--pdeathsig", "TERM", "--", ...root.args]

    Component.onCompleted: root.running = root.wanted
    onWantedChanged: {
        retry.stop();
        root.running = root.wanted;
    }
    onRunningChanged: root.running ? healthy.restart() : healthy.stop()
    onExited: if (root.wanted) retry.restart()

    property Timer _retry: Timer {
        id: retry
        interval: root._wait
        onTriggered: {
            root._wait = Math.min(root._wait * 2, 60000);
            if (root.wanted) root.running = true;
        }
    }
    property Timer _healthy: Timer {
        id: healthy
        interval: 60000
        onTriggered: root._wait = 1000
    }
}
