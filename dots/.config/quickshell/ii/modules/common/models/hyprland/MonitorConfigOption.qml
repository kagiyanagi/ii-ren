pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import "../"

// Live monitor layout, read from hyprctl. Edits apply immediately with
// `hyprctl keyword monitor` and persist to ~/.config/hypr/monitors.lua, which
// hyprland.lua sources after its own defaults when the file exists.
NestableObject {
    id: root

    property var monitors: []
    readonly property string savePath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/monitors.lua`)

    Component.onCompleted: root.fetch()

    function fetch(): void {
        fetchProc.running = true;
    }

    function updateMonitor(index: int, changes: var): void {
        let updated = root.monitors.slice();
        updated[index] = Object.assign({}, updated[index], changes);
        root.monitors = updated;
    }

    // Width and height as the compositor lays them out, i.e. swapped when the
    // display is rotated a quarter turn.
    function logicalWidth(m: var): real {
        return (m.transform === 1 || m.transform === 3) ? m.height : m.width;
    }

    function logicalHeight(m: var): real {
        return (m.transform === 1 || m.transform === 3) ? m.width : m.height;
    }

    function _monitorArg(m: var): string {
        if (m.disabled)
            return `${m.name},disable`;
        const base = `${m.name},${m.currentMode},${m.x}x${m.y},${m.scale}`;
        return (m.transform && m.transform !== 0) ? `${base},transform,${m.transform}` : base;
    }

    function _luaLine(m: var): string {
        if (m.disabled)
            return `hl.monitor({ output = "${m.name}", mode = "disable" })`;
        let line = `hl.monitor({ output = "${m.name}", mode = "${m.currentMode}", position = "${m.x}x${m.y}", scale = ${m.scale}`;
        if (m.transform && m.transform !== 0)
            line += `, transform = ${m.transform}`;
        return line + " })";
    }

    function applyMonitor(m: var): void {
        if (!m?.name)
            return;
        applyProc.command = ["hyprctl", "keyword", "monitor", root._monitorArg(m)];
        applyProc.running = true;
    }

    function save(): void {
        // A half-read monitor list would persist a layout that blanks a screen,
        // so write nothing rather than something incomplete.
        if (root.monitors.length === 0 || root.monitors.some(m => !m.name))
            return;
        const body = [
            "-- MANAGED BY THE SETTINGS APP (Hyprland > Displays)",
            ...root.monitors.map(m => root._luaLine(m))
        ].join("\n");
        saveProc.command = ["bash", "-c", `printf '%s\\n' '${StringUtils.shellSingleQuoteEscape(body)}' > '${root.savePath}'`];
        saveProc.running = true;
    }

    function applyAndSave(index: int): void {
        root.applyMonitor(root.monitors[index]);
        root.save();
    }

    Process {
        id: fetchProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(text).map(m => ({
                        name: m.name,
                        description: m.description,
                        width: m.width,
                        height: m.height,
                        refreshRate: m.refreshRate,
                        x: m.x,
                        y: m.y,
                        scale: m.scale,
                        transform: m.transform ?? 0,
                        disabled: m.disabled,
                        availableModes: m.availableModes ?? [],
                        currentMode: `${m.width}x${m.height}@${m.refreshRate.toFixed(2)}Hz`
                    }));
                } catch (e) {
                    console.log(`[MonitorConfigOption] Failed to parse monitors: ${e}`);
                }
            }
        }
    }

    Process { id: applyProc }
    Process { id: saveProc }
}
