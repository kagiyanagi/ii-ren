pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
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

    function set(on, until) {
        root.until = until
        root.inhibit = on
        Persistent.states.idle.inhibit = on
        Persistent.states.idle.until = until
        Persistent.states.idle.sessionId = root._sessionId
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
