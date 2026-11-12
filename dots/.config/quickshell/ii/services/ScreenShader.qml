pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.utils
import "screenShader.js" as Shader

/**
 * The one owner of Hyprland's decoration:screen_shader. Comfort View, Reading Mode
 * and Anti-flashbang each wrote their own shader into it, so turning one on replaced
 * the others and turning Comfort View or Reading Mode off cleared Anti-flashbang too.
 * Here they are composed into one generated shader (screenShader.js).
 *
 * Applied live with `hyprctl eval`, never `hyprctl reload`, and kept out of
 * shellOverrides/main.lua: a reload starts from the config again, so it is
 * applied once more after every reload, as floating mode's Lua is. The file is
 * generated under the state directory, named by its content so Hyprland sees a
 * new path and compiles it; the repo's files are never written.
 */
Singleton {
    id: root

    readonly property bool ready: Config.ready && Persistent.ready
    readonly property bool antiFlashbang: Persistent.states.hyprland.antiFlashbangShader
    readonly property string source: Shader.source({
        "comfort": HyprlandComfortView.effectiveActive ? { "intensity": HyprlandComfortView.intensity } : null,
        "reading": HyprlandReadingMode.effectiveActive ? { "intensity": HyprlandReadingMode.intensity, "paperTone": HyprlandReadingMode.paperTone } : null,
        "antiFlashbang": root.antiFlashbang
    })
    readonly property string directory: FileUtils.trimFileProtocol(`${Directories.state}/user/generated/screen-shader`)
    readonly property string fileName: root.source ? `${Qt.md5(root.source)}.glsl` : ""
    readonly property string path: root.fileName ? `${root.directory}/${root.fileName}` : ""

    function load() {
        root.migrate();
        applyDebounce.restart();
    }

    // Whether a shader of ours is on screen in this Lua state. Until one is, nothing
    // on means hands off: a screen_shader from the user's own custom/*.lua stays.
    property bool applied: false

    function apply() {
        if (!root.ready || (!root.source && !root.applied))
            return;
        root.applied = root.source !== "";
        applier.refresh();
    }

    function setAntiFlashbang(on) {
        Persistent.states.hyprland.antiFlashbangShader = on;
    }

    onSourceChanged: applyDebounce.restart()
    onReadyChanged: applyDebounce.restart()

    // A slider moves in integer steps, each a new shader for Hyprland to compile.
    // ponytail: fixed 200ms settle, not tied to a motion token -- nothing animates on it.
    Timer {
        id: applyDebounce
        interval: 200
        onTriggered: root.apply()
    }

    Connections {
        target: HyprlandSettings
        function onReloaded() {
            root.applied = false;
            root.apply();
        }
    }

    // Writes the file (or removes them all) and puts it on screen. Arguments only:
    // the shader text and the Lua never become part of the script.
    RefreshProcess {
        id: applier
        command: ["sh", "-c", 'mkdir -p "$1" || exit; '
            + 'if [ -n "$2" ]; then printf "%s" "$3" > "$1/$2.tmp" && mv -f "$1/$2.tmp" "$1/$2" || exit; fi; '
            + 'for f in "$1"/*.glsl; do [ "${f##*/}" = "$2" ] || rm -f "$f"; done; '
            + 'exec hyprctl eval "$4"',
            "sh", root.directory, root.fileName, root.source, Shader.lua(root.path, root.antiFlashbang)]
    }

    // Before the shell owned this, the shaders went into shellOverrides/main.lua,
    // pointing at files in the repo. Carry Anti-flashbang's state over and take
    // those lines out, once; an override that is not one of ours stays.
    function migrate() {
        if (!HyprlandSettings.overridesLoaded) {
            migrateWhenLoaded.enabled = true;
            return;
        }
        migrateWhenLoaded.enabled = false;
        const shader = HyprlandSettings.overrides["decoration:screen_shader"] ?? "";
        if (!/\/services\/hyprland(AntiFlashbang|ComfortView|ReadingMode)Shader\//.test(shader))
            return;
        const wasAntiFlashbang = shader.includes("AntiFlashbang");
        if (wasAntiFlashbang)
            root.setAntiFlashbang(true);
        const keys = ["decoration:screen_shader"];
        if (wasAntiFlashbang && HyprlandSettings.overrides["debug:damage_tracking"] === "1")
            keys.push("debug:damage_tracking");
        HyprlandSettings.resetKeys(keys);
    }

    Connections {
        id: migrateWhenLoaded
        enabled: false
        target: HyprlandSettings
        function onOverridesLoadedChanged() {
            root.migrate();
        }
    }
}
