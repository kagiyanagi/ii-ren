#!/usr/bin/env python3
"""The sidebar's audio dialogs cost nothing per app, and their cards keep their corners.

Each app row ran a `Desaturate`, an offscreen pass in a repeated delegate (DESIGN.md 8).
`check-effect-budget.py` never saw it, because the delegate is its own file: the dock's
blind spot. The mute button was a bare `MouseArea` with no states. Both are gone, and
this keeps them gone.

The device rows are `DialogListItem`s on a rounded card with no clip, so each row rounds
its own end corners. Which row is last depends on how many devices there are and whether
the "several devices" switch row is showing. A square corner there shows only on hover,
so the expressions are lifted out and evaluated under node for every combination.

`GlobalStates.requestVolumeDialog` is set by the media popup's audio-device pill, and for
as long as it existed nothing read it: the pill opened the sidebar and stopped there.
"""
import json
import re
import subprocess
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
MIXER = II / "modules/ii/sidebarDashboard/volumeMixer"
entry = (MIXER / "VolumeMixerEntry.qml").read_text()
content = (MIXER / "VolumeDialogContent.qml").read_text()
dialog = (MIXER / "VolumeDialog.qml").read_text()
sidebar = (II / "modules/ii/sidebarDashboard/SidebarDashboardContent.qml").read_text()

code = lambda s: re.sub(r"//.*", "", s)
for name, src in (("VolumeMixerEntry", code(entry)), ("VolumeDialogContent", code(content))):
    for effect in ("Desaturate", "ColorOverlay", "MultiEffect", "OpacityMask", "GraphicalEffects", "layer.enabled"):
        assert effect not in src, f"{name}: {effect} runs once per row"
assert "MouseArea" not in code(entry), "VolumeMixerEntry: the mute button must be a RippleButton, a MouseArea has no states"
assert "backgroundHeight" not in dialog, "VolumeDialog: a fixed height is a void under one app row"

switch = re.search(r"StyledSwitch \{(.*?)\}", content, re.S)
assert switch and re.search(r"checkable:\s*false", switch.group(1)), "VolumeDialogContent: the switch must not toggle itself"
assert re.search(r"checked:\s*root\.multiple", switch.group(1)), "VolumeDialogContent: the switch must read root.multiple"

reader = re.search(r"function onRequestVolumeDialogChanged\(\) \{(.*?)\n        \}", sidebar, re.S)
assert reader, "SidebarDashboardContent: nothing reads GlobalStates.requestVolumeDialog"
assert "GlobalStates.requestVolumeDialog = false" in reader.group(1), "the request must be consumed, or a second tap does nothing"
assert "root.showAudioOutputDialog = true" in reader.group(1), "the request must open the output dialog"


def lift(block_start, prop):
    block = content[content.index(block_start):]
    return re.search(rf"{prop}:\s*(.+)", block).group(1)


show_multiple = re.search(r"readonly property bool showMultiple:\s*(.+)", content).group(1)
device_top = lift("delegate: DialogListItem", "topLeftRadius")
device_bottom = lift("delegate: DialogListItem", "bottomLeftRadius")
multiple_top = lift("id: multipleRow", "topLeftRadius")
multiple_bottom = lift("id: multipleRow", "bottomLeftRadius")

JS = f"""
const Appearance = {{ rounding: {{ large: 1 }} }};
const out = [];
for (let n = 0; n <= 4; n++) for (const multiple of [false, true]) {{
    const root = {{ devices: new Array(n), multiple }};
    with (root) root.showMultiple = {show_multiple};  // the binding reads root's own members unqualified
    const rows = [];
    for (let index = 0; index < n; index++) rows.push([{device_top}, {device_bottom}]);
    if (root.showMultiple) rows.push([{multiple_top}, {multiple_bottom}]);
    out.push({{ n, multiple, showMultiple: root.showMultiple, rows }});
}}
console.log(JSON.stringify(out));
"""
cases = json.loads(subprocess.run(["node", "-e", JS], capture_output=True, text=True, check=True).stdout)
for c in cases:
    assert c["showMultiple"] == (c["n"] > 1 or c["multiple"]), f"switch row shown wrongly: {c}"
    for i, (top, bottom) in enumerate(c["rows"]):
        assert top == (1 if i == 0 else 0), f"row {i} top corner wrong: {c}"
        assert bottom == (1 if i == len(c["rows"]) - 1 else 0), f"row {i} bottom corner wrong: {c}"

print(f"ok: no per-row effect, the pill's request is read, and {len(cases)} device-card layouts keep their corners")
