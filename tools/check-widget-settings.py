#!/usr/bin/env python3
"""Widget settings must name declared keys and change the behaviour they guard.

Unknown JsonObject members read as undefined: album colours never turned on,
the PC widgets ignored the position lock, lock centring could not be configured,
and the animation multiplier always fell back to one. Several widgets also
overrode the base's lock visibility with a retired centerWidget preference.

Run the actual bindings under node using defaults read from Config.qml, including
both centring axes, scaled widgets and a zero gap. No live settings are touched.
"""
import json
import re
import subprocess
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
WIDGETS = II / "modules/ii/background/widgets"
SCHEMA = (II / "modules/common/Config.qml").read_text()
BASE = (WIDGETS / "AbstractBackgroundWidget.qml").read_text()


def config_default(path):
    source = SCHEMA
    parts = path.split(".")
    indent = " " * 12  # Direct members of configOptionsJsonAdapter.
    for group in parts[:-1]:
        match = re.search(rf"^{indent}property JsonObject {group}: JsonObject \{{\n", source, re.M)
        assert match, f"Config has no group {path}"
        end = re.search(rf"^{indent}\}}", source[match.end():], re.M)
        assert end, f"Config group {group} has no closing brace"
        source = source[match.end():match.end() + end.start()]
        indent += " " * 4
    match = re.search(rf"^{indent}property (?:bool|real|string) {parts[-1]}: ([^\n]+)", source, re.M)
    assert match, f"Config has no setting {path}"
    return json.loads(match[1].split(" //")[0])


def binding(source, name):
    match = re.search(rf"^ +(?:readonly )?property [\w<>]+ {name}: ([^\n]+)", source, re.M)
    assert match, f"Missing binding {name}"
    return match[1]


options = {}
for path in (
    "appearance.animationMultiplier", "background.widgets.media.dynamicAlbumColors",
    "background.widgets.lockWidgetPositions", "lock.centerAlignment", "lock.centerSpacing",
):
    group = options
    parts = path.split(".")
    for part in parts[:-1]:
        group = group.setdefault(part, {})
    group[parts[-1]] = config_default(path)

android = (WIDGETS / "media/AndroidMediaWidget.qml").read_text()
pc_media = (WIDGETS / "pc_widgets/media/MediaWidget.qml").read_text()
resources = (WIDGETS / "pc_widgets/resources/ResourcesWidget.qml").read_text()
assert "locked: root._desktopPositionsLocked" in pc_media, "PC media bypasses the desktop lock"
assert "visible: opacity > 0 && !root._desktopPositionsLocked" in resources, "Resources bypasses the desktop lock"
for path in WIDGETS.rglob("*.qml"):
    source = path.read_text()
    assert not re.search(r"Config\.options\.lock\.centerWidget\b", source), f"{path}: retired lock selection"
    assert "Config.options.background.widgetsLocked" not in source, f"{path}: nonexistent desktop lock"

offsets = []
for axis in ("X", "Y"):
    match = re.search(rf"readonly property real centeredOffset{axis}: \{{\n(.*?)\n    \}}", BASE, re.S)
    assert match, f"Missing centred offset for {axis}"
    offsets.append(match[1])

bindings = {
    "colours": binding(android, "useDynamicColors"),
    "locked": binding(BASE, "_desktopPositionsLocked"),
    "visible": binding(BASE, "visibleWhenLocked"),
    "multiplier": binding((II / "modules/common/Appearance.qml").read_text(), "animMultiplier"),
}
subprocess.run(["node", "-e", f"""
const assert = require('node:assert/strict');
const Config = {{options: {json.dumps(options)}}};
const expressions = {json.dumps(bindings)};
const root = {{artSource: 'file:///cover.png'}};
const evaluate = name => new Function('Config', 'root', 'lockBehavior',
    'return (' + expressions[name] + ');')(Config, root, root.lockBehavior);

assert.equal(evaluate('colours'), false, 'default album colours');
Config.options.background.widgets.media.dynamicAlbumColors = true;
assert.equal(evaluate('colours'), true, 'album colours enabled');
root.artSource = '';
assert.equal(evaluate('colours'), false, 'no album art');
Config.options.background.widgets.media.dynamicAlbumColors = false;
root.artSource = 'file:///cover.png';
assert.equal(evaluate('colours'), false, 'album colours disabled again');

for (const locked of [false, true, false]) {{
    Config.options.background.widgets.lockWidgetPositions = locked;
    assert.equal(evaluate('locked'), locked, 'desktop position lock');
}}
for (const [behaviour, visible] of [['hide', false], ['keep', true], ['center', true], ['lockOnly', true]]) {{
    root.lockBehavior = behaviour;
    assert.equal(evaluate('visible'), visible, behaviour);
}}
assert.equal(evaluate('multiplier'), 1, 'default animation multiplier');
for (const multiplier of [0, 0.25, 0.5, 2]) {{
    Config.options.appearance.animationMultiplier = multiplier;
    assert.equal(evaluate('multiplier'), multiplier, 'animation multiplier ' + multiplier);
}}

const bodies = {json.dumps(offsets)};
const widgets = [{{instanceId: 'a'}}, {{instanceId: 'b'}}];
root.widgetSizes = {{a: {{width: 100, height: 60, scale: 1}}, b: {{width: 200, height: 80, scale: 0.5}}}};
const offset = (axis, index, count = 2) => {{
    root.visualWidth = 100;
    root.visualHeight = index === 0 ? 60 : 40;
    return new Function('Config', 'root', 'centeredWidgetCount', 'centeredWidgetIndex',
        'centeredWidgetsList', bodies[axis])(Config, root, count, index, widgets);
}};
assert.equal(Config.options.lock.centerAlignment, 'horizontal');
assert.equal(Config.options.lock.centerSpacing, 20);
for (const spacing of [0, 20, 40]) {{
    Config.options.lock.centerSpacing = spacing;
    Config.options.lock.centerAlignment = 'horizontal';
    assert.equal(offset(0, 0), -(100 + spacing) / 2);
    assert.equal(offset(0, 1), (100 + spacing) / 2);
    assert.equal(offset(1, 0), 0);
    Config.options.lock.centerAlignment = 'vertical';
    assert.equal(offset(0, 0), 0);
    assert.equal(offset(1, 0), -(40 + spacing) / 2);
    assert.equal(offset(1, 1), (60 + spacing) / 2);
    for (const axis of [0, 1]) {{
        assert.equal(offset(axis, 0, 0), 0, 'empty group');
        assert.equal(offset(axis, 0, 1), 0, 'single centred widget');
    }}
}}
"""], check=True)
print("ok: widget colour, position lock, lock layout and animation settings work")
