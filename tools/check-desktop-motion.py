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
Photo widgets must also stop their AnimatedImage behind windows and resume on
an exposed desktop; a nonexistent GlobalStates flag left all five playing.
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

photos = II / "modules/ii/background/widgets/photo"
photo_bodies = []
for path in sorted(photos.glob("*.qml")):
    source = path.read_text()
    if "AnimatedImage {" not in source:
        continue
    body = re.search(r"readonly property bool shouldPlay: \{\n(.*?)\n    \}", source, re.S)
    assert body, f"{path.name}: animated photo has no playback gate"
    assert "!root.coveredByWindows" in body[1], f"{path.name}: photo keeps playing behind windows"
    assert "GlobalStates.activeWorkspaceHasWindows" not in source, f"{path.name}: nonexistent workspace flag"
    assert "playing: root.shouldPlay" in source and "paused: !root.shouldPlay" in source, \
        f"{path.name}: AnimatedImage does not follow the playback gate"
    photo_bodies.append([path.name, body[1]])
assert len(photo_bodies) >= 5, "the five photo variants are no longer covered"
subprocess.run(["node", "-e", f"""
const assert = require('node:assert/strict');
for (const [name, body] of {json.dumps(photo_bodies)}) {{
    const shouldPlay = new Function('root', 'GlobalStates', body);
    const root = {{visible: true, opacity: 1, isAnimated: true, coveredByWindows: false}};
    const GlobalStates = {{screenLocked: false}};
    assert.equal(shouldPlay(root, GlobalStates), true, name + ': exposed desktop');
    for (const [property, value] of [['coveredByWindows', true], ['visible', false], ['opacity', 0], ['isAnimated', false]]) {{
        const previous = root[property];
        root[property] = value;
        assert.equal(shouldPlay(root, GlobalStates), false, name + ': ' + property);
        root[property] = previous;
        assert.equal(shouldPlay(root, GlobalStates), true, name + ': resumes after ' + property);
    }}
    GlobalStates.screenLocked = true;
    assert.equal(shouldPlay(root, GlobalStates), false, name + ': locked');
}}
"""], check=True)

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
