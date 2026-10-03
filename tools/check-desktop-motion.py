#!/usr/bin/env python3
"""Desktop animation stops while windows hide the wallpaper.

A desktop widget's wave, its spinning album art and a weather shader each redraw
the whole wallpaper surface every frame, and kept doing it under a tiled terminal
for as long as a track played: frames nobody could see, on integrated graphics.
HyprlandData.wallpaperCovered(monitor) says when a tiled or fullscreen window sits
on that monitor's active workspace; floating windows leave the desktop partly in
view and do not count, and the lock screen's workspace has no windows.

This evaluates that function under node for each case, and asserts every ambient
motion on the desktop is gated on it.
"""
import json
import re
import subprocess
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
data = (II / "services/HyprlandData.qml").read_text()
m = re.search(r"function wallpaperCovered\(monitorName\) \{\n(.*?)\n    \}\n", data, re.S)
assert m, "HyprlandData.qml: no wallpaperCovered(monitorName)"

CASES = [
    ("a tiled window", [{"workspace": {"id": 2}, "floating": False, "fullscreen": 0}], True),
    ("only a floating window", [{"workspace": {"id": 2}, "floating": True, "fullscreen": 0}], False),
    ("a fullscreen floating window", [{"workspace": {"id": 2}, "floating": True, "fullscreen": 1}], True),
    ("a tiled window on another workspace", [{"workspace": {"id": 3}, "floating": False, "fullscreen": 0}], False),
    ("an empty workspace", [], False),
]
js = f"""
const assert = require("assert");
const cases = {json.dumps(CASES)};
for (const [name, windows, want] of cases) {{
    const root = {{ monitors: [{{ name: "eDP-1", activeWorkspace: {{ id: 2 }} }}], windowList: windows }};
    const wallpaperCovered = monitorName => {{ {m.group(1)} }};
    assert.strictEqual(wallpaperCovered("eDP-1"), want, name);
    assert.strictEqual(wallpaperCovered("HDMI-A-1"), false, name + ", asked about an unknown monitor");
}}
"""
subprocess.run(["node", "-e", js], check=True)

base = (II / "modules/ii/background/widgets/AbstractBackgroundWidget.qml").read_text()
assert re.search(r"coveredByWindows: !root\.isPreview && HyprlandData\.wallpaperCovered\(", base), \
    "AbstractBackgroundWidget: coveredByWindows must skip previews (the settings app would start hyprctl queries)"
for rel, pattern in [
    ("modules/ii/background/widgets/media/ExpressiveMediaWidget.qml", r"FrameAnimation \{\n\s*running: [^\n]*!root\.coveredByWindows"),
    ("modules/ii/background/widgets/media/ExpressiveMediaWidget.qml", r"animateWave: [^\n]*!root\.coveredByWindows"),
    ("modules/ii/background/widgets/media/AndroidMediaWidget.qml", r"animateWave: [^\n]*!root\.coveredByWindows"),
    ("modules/ii/background/Background.qml", r"WeatherEffects \{(?:(?!\n        \}).)*paused: HyprlandData\.wallpaperCovered\("),
]:
    assert re.search(pattern, (II / rel).read_text(), re.S), f"{rel}: desktop motion no longer stops under windows ({pattern[:40]}...)"

print("ok: desktop motion pauses under tiled and fullscreen windows only")
