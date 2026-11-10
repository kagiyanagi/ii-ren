pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs
import "hyprlandOverrides.js" as Overrides

Singleton {
    id: root

    signal reloaded()

    // Trust boundary: hyprset.lua writes these into main.lua as Lua source, unescaped.
    // Do not loosen this character class.
    function _hasUnsafeChars(...values) {
        return values.some(v => /['"\\`$|&;]/.test(String(v)))
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
        root.updateKeys(entries, [])
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
        root.updateKeys({}, keys)
    }

    // One `bash -c` chain for the lot: each hyprset rewrites main.lua whole, so two
    // running at once can lose one's write. Keys and values go in as arguments, never
    // into the script, and a value with spaces ("5 10 5 10") stays one value.
    function updateKeys(entries, resetKeys) {
        var steps = []
        var args = []
        function arg(v) {
            args.push(String(v))
            return '"${' + args.length + '}"'
        }
        var keys = Object.keys(entries)
        for (var i = 0; i < keys.length; i++) {
            var key = keys[i]
            var value = entries[key]
            if (root._hasUnsafeChars(value, key)) {
                console.error("[HyprlandSettings] Unsafe characters rejected:", key, value)
                continue
            }
            if (!key.includes(":")) continue
            steps.push('"$0" hyprset key ' + arg(key) + " " + arg(value))
        }
        for (var j = 0; j < resetKeys.length; j++) {
            if (root._hasUnsafeChars(resetKeys[j])) {
                console.error("[HyprlandSettings] Unsafe characters rejected:", resetKeys[j])
                continue
            }
            steps.push('"$0" hyprset reset ' + arg(resetKeys[j]))
        }
        if (steps.length === 0) return
        Quickshell.execDetached(["bash", "-c", steps.join(" && "), Directories.cliPath].concat(args))
        root._queueReload()
    }

    // What main.lua overrides, key -> value as written ("18", "false", "dwindle"):
    // the user's own choices, which hyprctl getoption cannot tell from the defaults.
    property var overrides: ({})
    property bool overridesLoaded: false

    FileView {
        id: overridesFile
        // HOME, not XDG_CONFIG_HOME: the path hyprset.lua writes.
        path: `${FileUtils.trimFileProtocol(Directories.home)}/.config/hypr/hyprland/shellOverrides/main.lua`
        watchChanges: true
        onFileChanged: overridesReload.restart()
        onLoaded: {
            root.overrides = Overrides.parse(overridesFile.text())
            root.overridesLoaded = true
        }
        onLoadFailed: error => {
            root.overrides = ({})
            root.overridesLoaded = true
        }
    }

    // A chain rewrites the file once per key.
    Timer {
        id: overridesReload
        interval: 100
        onTriggered: overridesFile.reload()
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
