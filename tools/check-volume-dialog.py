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

With devices combined, each member row carries a slider over that device's own volume,
which is its balance against the others; the combined device is the master. That balance
is only worth having if it survives the module being reloaded, which happens every time a
member joins or leaves: the service used to level *every* member to unity on each reload,
so adding a third speaker silently flattened the first two. Only a device that is joining
is levelled now, and the rule is evaluated under node. The module is also loaded with
latency compensation for playback, so wired speakers wait for a Bluetooth one instead of
echoing ~200ms ahead of it.

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
audio = (II / "services/Audio.qml").read_text()

code = lambda s: re.sub(r"//.*", "", s)
for name, src in (("VolumeMixerEntry", code(entry)), ("VolumeDialogContent", code(content))):
    for effect in ("Desaturate", "ColorOverlay", "MultiEffect", "OpacityMask", "GraphicalEffects", "layer.enabled"):
        assert effect not in src, f"{name}: {effect} runs once per row"
assert "MouseArea" not in code(entry), "VolumeMixerEntry: the mute button must be a RippleButton, a MouseArea has no states"
wifi = (II / "modules/ii/sidebarDashboard/wifiNetworks/WifiDialog.qml").read_text()
height = re.search(r"backgroundHeight:\s*(.+)", dialog)
assert height and height.group(1) == re.search(r"backgroundHeight:\s*(.+)", wifi).group(1), \
    "VolumeDialog: must share the Wi-Fi dialog's screen-scaled height, not a fixed 600 or its content's"
assert re.search(r"VolumeDialogContent \{[^}]*Layout\.fillHeight:\s*true", dialog), "VolumeDialog: the body must fill the card and scroll"

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

balance = re.search(r"visible:\s*root\.combined && deviceRow\.inUse(.*?)StyledText", content, re.S)
assert balance, "VolumeDialogContent: a combined member row has no balance slider"
assert re.search(r"onMoved:\s*deviceRow\.modelData\.audio\.volume = value", balance.group(1)), "the balance slider must write the member's own volume"
assert re.search(r"PwObjectTracker \{[^}]*objects:\s*root\.devices", content), "a device's volume is unreadable unless tracked"

timer = re.search(r"property Timer levelTimer: Timer \{(.*?)\n        \}", audio, re.S).group(1)
assert "combinedNames" not in timer, "Audio: the reload timer must not level every member, that flattens the balance"
assert "stream.joining.forEach" in timer and "stream.joining = []" in timer, "Audio: the reload timer must level the joining members, once"
joining = re.search(r"(const joining = .+;)\n\s*(stream\.joining = .+;)", audio)
assert joining, "Audio: could not lift the joining rule out of setCombinedNames"
JOIN = f"""
const out = %s.map(([previous, names, pending]) => {{
    const stream = {{ joining: pending }};
    {joining.group(1)}
    {joining.group(2)}
    return stream.joining;
}});
console.log(JSON.stringify(out));
"""
join_cases = [
    (([], ["A"], []), []),                         # multi-device on: one member, nothing combined yet
    ((["A"], ["A", "B"], []), ["A", "B"]),         # going combined levels the device in use too
    ((["A", "B"], ["A", "B", "C"], []), ["C"]),    # later, only the newcomer: A and B keep their balance
    ((["A", "B", "C"], ["A", "C"], ["C"]), ["C"]), # C left pending by a reload still in flight
    ((["A", "B", "C"], ["A", "B"], ["C"]), []),    # a pending member that leaves is dropped
    ((["A", "B"], [], ["B"]), []),                 # multi-device off: nothing combined, nothing pending
]
got = json.loads(subprocess.run(["node", "-e", JOIN % json.dumps([c for c, _ in join_cases])],
                                capture_output=True, text=True, check=True).stdout)
for (case, want), line in zip(join_cases, got):
    assert line == want, f"Audio joining: {case} gave {line}, want {want}"

JS_COMBINE = f"""
const c = require({json.dumps(str(II / "services/combineStream.js"))});
console.log(JSON.stringify([c.command(true, ["a", "b"], "x")[4], c.command(false, ["a", "b"], "x")[4]]));
"""
sink_args, source_args = json.loads(subprocess.run(["node", "-e", JS_COMBINE], capture_output=True, text=True, check=True).stdout)
assert "combine.latency-compensate = true" in sink_args, "combineStream: playback must compensate latency, or Bluetooth echoes behind the rest"
assert "combine.latency-compensate = false" in source_args, "combineStream: capture has no listener to align"

print(f"ok: no per-row effect, the pill's request is read, and {len(cases)} device-card layouts keep their corners,"
      f" and {len(join_cases)} member changes level only the newcomers")
