pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs

Singleton {
    id: root

    signal reloaded()

    // Trust boundary: these values reach `bash -c`. Do not loosen this character class.
    function _hasUnsafeChars(...values) {
        return values.some(v => /['"\\`$|&;]/.test(String(v)))
    }

    // NOTE: bash -c "cmd1 && cmd2 && ..." prevents a race between separate hyprset calls
    function _execChained(parts) {
        if (parts.length > 0) {
            Quickshell.execDetached(["bash", "-c", parts.join(" && ")])
            root._queueReload()
        }
    }

    // hyprset only rewrites shellOverrides/main.lua; Hyprland keeps running the
    // values it parsed at startup until told to re-source it. Debounced because
    // a slider drag fires this on every step.
    function _queueReload() {
        reloadTimer.restart()
    }

    Timer {
        id: reloadTimer
        interval: 400
        onTriggered: Quickshell.execDetached(["hyprctl", "reload"])
    }

    function changeKey(key, value) {
        if (root._hasUnsafeChars(value, key)) {
            console.error("[HyprlandSettings] Unsafe characters rejected:", key, value)
            return
        }
        if (!key.includes(":")) return
        Quickshell.execDetached([Directories.cliPath, "hyprset", "key", key, String(value)])
        root._queueReload()
    }

    function changeAnimation(animName, style) {
        if (root._hasUnsafeChars(animName, style)) {
            console.error("[HyprlandSettings] Unsafe characters rejected:", animName, style)
            return
        }
        Quickshell.execDetached([Directories.cliPath, "hyprset", "anim", animName, String(style)])
        root._queueReload()
    }

    function setLayout(layout) {
        if (layout !== "default" && layout !== "scrolling" && layout !== "dwindle" && layout !== "monocle" && layout !== "master") return
        // console.log("[HyprlandSettings] Setting layout to", layout)
        changeKey("general:layout", layout)
        Persistent.states.hyprland.layout = layout
    }

    function setRounding(rounding) {
        changeKey("decoration:rounding", rounding)
    }

    function setKeys(entries) {
        var parts = []
        var keys = Object.keys(entries)
        for (var i = 0; i < keys.length; i++) {
            var key = keys[i]
            var value = entries[key]
            if (root._hasUnsafeChars(value, key)) {
                console.error("[HyprlandSettings] Unsafe characters rejected:", key, value)
                continue
            }
            if (!key.includes(":")) continue
            parts.push(Directories.cliPath + " hyprset key " + key + " " + String(value))
        }
        root._execChained(parts)
    }

    function reset(key) {
        if (root._hasUnsafeChars(key)) {
            console.error("[HyprlandSettings] Unsafe characters rejected:", key)
            return
        }
        Quickshell.execDetached([Directories.cliPath, "hyprset", "reset", key])
        root._queueReload()
    }

    function resetKeys(keys) {
        var parts = []
        for (var i = 0; i < keys.length; i++) {
            var key = keys[i]
            if (root._hasUnsafeChars(key)) {
                console.error("[HyprlandSettings] Unsafe characters rejected:", key)
                continue
            }
            parts.push(Directories.cliPath + " hyprset reset " + key)
        }
        root._execChained(parts)
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                root.reloaded()
            }
        }
    }
}
