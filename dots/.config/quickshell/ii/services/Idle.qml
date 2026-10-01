pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    property alias inhibit: idleInhibitor.enabled
    inhibit: false

    // When a timed keep-awake ends, epoch ms; 0 is until turned off.
    property real until: 0
    // Ticks while a timed one runs, so a countdown can bind to it. Wall clock,
    // not a single-shot timer: a monotonic interval would outlast a suspend.
    property real now: Date.now()
    // Awake while any of these processes runs, [{ pid, name, cls }]; empty is
    // by time. PIDs, not windows: an app closed to the tray still counts.
    property list<var> anchors: []
    readonly property real remaining: inhibit && until > 0 ? Math.max(0, until - now) : 0
    // "1h 20m", "12m", "45s": minutes round up, so 5m reads 5m until it is 4m.
    readonly property string remainingText: {
        const s = Math.ceil(remaining / 1000)
        if (s < 60) return `${s}s`
        const m = Math.ceil(s / 60)
        return m < 60 ? `${m}m` : m % 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m / 60}h`
    }

    readonly property string _sessionId: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""

    Timer {
        id: restoreTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (!Persistent.ready) return
            const storedId = Persistent.states.idle.sessionId || ""
            if (storedId === root._sessionId) {
                root.until = Persistent.states.idle.until ?? 0
                root.anchors = [...(Persistent.states.idle.anchors ?? [])]
                root.inhibit = Persistent.states.idle.inhibit ?? false
                tick.triggered()
            } else {
                root.inhibit = false
            }
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged() { restoreTimer.restart() }
    }

    // On with the last picked duration, as a tap on the tile does.
    function toggleInhibit(active = null) {
        const on = active !== null ? active : !root.inhibit
        if (on) start(Persistent.states.idle.minutes ?? 0)
        else set(false, 0)
    }

    // minutes 0 is until turned off. Also remembered for the next toggle.
    function start(minutes) {
        Persistent.states.idle.minutes = minutes
        root.now = Date.now()
        set(true, minutes > 0 ? root.now + minutes * 60000 : 0)
    }

    // Adds the process to the ones keeping it awake, or a second tap drops it.
    // Picking one is a mode, as a duration is: it replaces a timed one.
    function toggleAnchor(pid, name, cls) {
        const kept = root.anchors.filter(a => a.pid !== pid)
        if (kept.length === root.anchors.length) kept.push({ pid, name, cls })
        set(kept.length > 0, 0, kept)
    }

    function set(on, until, anchors = []) {
        root.until = until
        root.anchors = anchors
        root.inhibit = on
        Persistent.states.idle.inhibit = on
        Persistent.states.idle.until = until
        Persistent.states.idle.anchors = anchors
        Persistent.states.idle.sessionId = root._sessionId
    }

    // A process exiting sends the shell nothing, and a closed window is not an
    // exited process, so the anchors are polled. The last one gone ends it.
    Timer {
        id: anchorTick
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.inhibit && root.anchors.length > 0
        onTriggered: {
            alive.pids = root.anchors.map(a => a.pid)
            alive.running = true
        }
    }

    Process {
        id: alive
        property list<int> pids: []
        command: ["ps", "-o", "pid=", "-p", pids.join(",")]
        stdout: StdioCollector {
            onStreamFinished: {
                const live = text.split(/\s+/).filter(Boolean).map(Number)
                // One picked while ps ran was not asked about, so it stays.
                const kept = root.anchors.filter(a => !alive.pids.includes(a.pid) || live.includes(a.pid))
                if (kept.length < root.anchors.length) root.set(kept.length > 0, 0, kept)
            }
        }
    }

    Timer {
        id: tick
        interval: 1000
        repeat: true
        running: root.inhibit && root.until > 0
        onTriggered: {
            root.now = Date.now()
            if (root.inhibit && root.until > 0 && root.now >= root.until) root.set(false, 0)
        }
    }

    IdleInhibitor {
        id: idleInhibitor
        window: PanelWindow {
            // Inhibitor requires a "visible" surface
            // Actually not lol
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            // Just in case...
            anchors {
                right: true
                bottom: true
            }
            // Make it not interactable
            mask: Region {
                item: null
            }
        }
    }
}
