#!/usr/bin/env python3
"""The bar knows its windows the moment it is built, not after the next window event.

The bar is torn down under the lock and built again on every unlock. HyprlandData passes
on no hyprctl reply identical to the last (check-hyprland-data.py), so a `Connections`
handler on `windowListChanged` never ran for a bar built after the list had settled: its
workspaces showed numerals instead of app icons, and the adaptive background stayed off,
until some window opened, closed or moved. What the bar derives from HyprlandData is
therefore a binding, which is evaluated when the bar is created.

This asserts no bar file fills state from a HyprlandData change handler, then runs the
bindings under node against a window list that was there before the bar: the workspace
icons (this monitor's tiled windows, left to right, without reordering the shared list)
and the adaptive background (a tiled window on this monitor's active workspace).
Monitor ids deliberately differ from screen indices, as they do after hotplug;
filtering bar.screenList must not change which physical monitor a bar reads.
"""
import json
import re
import subprocess
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
WORKSPACES = (II / "modules/ii/bar/Workspaces.qml").read_text()
BACKGROUNDS = {f: (II / f).read_text() for f in (
    "modules/ii/bar/Bar.qml", "modules/ii/bar/BarContent.qml", "modules/ii/verticalBar/VerticalBar.qml")}


def blocks(src, head):
    """Each `head {...}` block's body, braces matched."""
    for m in re.finditer(rf"\b{head}\s*\{{", src):
        depth, i = 1, m.end()
        while depth:
            depth += {"{": 1, "}": -1}.get(src[i], 0)
            i += 1
        yield src[m.end():i - 1]


for path in sorted([*(II / "modules/ii/bar").rglob("*.qml"), *(II / "modules/ii/verticalBar").rglob("*.qml")]):
    for body in blocks(path.read_text(), "Connections"):
        assert not re.search(r"target:\s*HyprlandData\b", body), (
            f"{path.relative_to(II)}: bar state filled from a HyprlandData change handler; "
            "a bar built after the data settled never gets it -- bind it instead")

icons = re.search(r"readonly property var monitorWindows: (.*?)\n(?= {4}\S)", WORKSPACES, re.S)
assert icons, "Workspaces.qml: monitorWindows is not a binding"
screen_index = re.search(r"readonly property int monitorIndex: (.*)", WORKSPACES).group(1)
backgrounds = {}
for f, src in BACKGROUNDS.items():
    m = re.search(r"\n( *)readonly property bool hasActiveWindows: \{\n(.*?)\n\1\}\n", src, re.S)
    assert m, f"{f}: hasActiveWindows is not a binding"
    backgrounds[f] = m.group(2)

JS = f"""
const assert = require("assert");
const windows = [
    {{ class: "b", monitor: 17, floating: false, at: [900, 0], workspace: {{ id: 1 }} }},
    {{ class: "a", monitor: 17, floating: false, at: [0, 0], workspace: {{ id: 1 }} }},
    {{ class: "f", monitor: 17, floating: true, at: [10, 0], workspace: {{ id: 2 }} }},
    {{ class: "o", monitor: 41, floating: false, at: [0, 0], workspace: {{ id: 3 }} }},
];
const HyprlandData = {{
    windowList: windows,
    monitors: [{{ id: 17, name: 'DP-1', activeWorkspace: {{ id: 1 }} }},
               {{ id: 41, name: 'HDMI-A-1', activeWorkspace: {{ id: 2 }} }}],
}};
const Quickshell = {{ iconPath: (name, fallback) => "icon:" + name,
    screens: [{{ name: 'HDMI-A-1' }}, {{ name: 'DP-1' }}] }};
const AppSearch = {{ guessIcon: cls => cls }};
const Config = {{ options: {{ bar: {{ barBackgroundStyle: 2 }} }} }};

const root = {{ monitorIndex: 0, monitor: {{ id: 17, name: 'DP-1' }}, screen: {{ name: 'DP-1' }} }};
assert.equal(({screen_index}), 1, 'workspace-map slots followed the filtered bar list');
root.monitor = null;
assert.equal(({screen_index}), 0, 'a bar without its screen during construction has no safe map slot');
root.monitor = {{ id: 17, name: 'DP-1' }};
assert.deepStrictEqual(({icons.group(1)}), [
    {{ icon: "icon:a", workspace: 1 }}, {{ icon: "icon:b", workspace: 1 }},
], "a new bar's workspace icons are not this monitor's tiled windows, left to right");
assert.deepStrictEqual(windows.map(w => w.class), ["b", "a", "f", "o"], "the icons reordered HyprlandData's window list");

for (const [file, body] of Object.entries({json.dumps(backgrounds)})) {{
    const covered = name => {{
        const root = {{ monitorIndex: 0, screen: {{ name }} }}, barRoot = root;
        return new Function("root", "barRoot", "HyprlandData", "Config", body)(root, barRoot, HyprlandData, Config);
    }};
    Config.options.bar.barBackgroundStyle = 2;
    assert.strictEqual(covered('DP-1'), true, file + ": a new bar has no adaptive background over a tiled window");
    assert.strictEqual(covered('HDMI-A-1'), false, file + ": a floating window gave the bar its adaptive background");
    assert.strictEqual(covered('disconnected'), false, file + ": a missing monitor borrowed another bar's background");
    Config.options.bar.barBackgroundStyle = 1;
    assert.strictEqual(covered('DP-1'), false, file + ": hasActiveWindows worked outside the adaptive style");
}}
console.log("ok: a bar built after the window list settled shows its icons and adaptive background at once");
"""
subprocess.run(["node", "-e", JS], check=True)
