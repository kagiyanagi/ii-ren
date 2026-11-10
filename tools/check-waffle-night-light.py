#!/usr/bin/env python3
"""Waffle's eye-protection switches use real APIs and never act on state updates.

The old page read missing properties and wrote services from onCheckedChanged,
including Reading Mode's readonly active property. Evaluate its real bindings and
click handlers with readonly service state. Also run ToggleItem in Qt with plain
visual stubs: switch and label clicks each emit once, external changes emit nothing,
and the checked binding survives clicks. No screen effects or settings are changed.
"""
import json
import re
import subprocess
import tempfile
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
page = (II / "modules/waffle/actionCenter/nightLight/NightLightControl.qml").read_text()
row = (II / "modules/waffle/actionCenter/ToggleItem.qml").read_text()
assert "onCheckedChanged" not in page
assert "checkable: false" in row
assert not re.search(r"\bchecked\s*=(?!=)", row)
assert row.count("onClicked: root.clicked()") == 2
rows = re.findall(r"ToggleItem \{(.*?)\n                \}", page, re.S)
assert len(rows) == 4
bindings = [re.search(r"checked: (.*)", r)[1] for r in rows]
actions = [re.search(r"onClicked: (.*)", r)[1] for r in rows]
for svc, prop, action in (("Hyprsunset", "temperatureActive", "toggleTemperature"),
                          ("HyprlandReadingMode", "active", "toggleManual"),
                          ("HyprlandAntiFlashbangShader", "enabled", "toggle")):
    source = (II / f"services/{svc}.qml").read_text()
    assert re.search(rf"property bool {prop}\b", source)
    assert f"function {action}(" in source
assert "property JsonObject night: JsonObject" in (II / "modules/common/Config.qml").read_text()
subprocess.run(["node", "-e", "'use strict';\n" + r'''
const assert = require('node:assert/strict');
const state = [false, false, false, false], calls = [0, 0, 0, 0];
const night = {};
Object.defineProperty(night, 'automatic', {get: () => state[0], set: v => {state[0] = v; calls[0]++}});
const Config = {options: {light: {night}}};
const Hyprsunset = {get temperatureActive() {return state[1]}, toggleTemperature() {state[1] = !state[1]; calls[1]++}};
const HyprlandReadingMode = {get active() {return state[2]}, toggleManual(v) {state[2] = v; calls[2]++}};
const HyprlandAntiFlashbangShader = {get enabled() {return state[3]}, toggle() {state[3] = !state[3]; calls[3]++}};
''' + f"""
const reads = {json.dumps(bindings)}.map(s => () => eval(s));
const clicks = {json.dumps(actions)}.map(s => () => eval(s));
reads.forEach(read => assert.equal(read(), false));
state.fill(true);
reads.forEach(read => assert.equal(read(), true));
assert.deepEqual(calls, [0, 0, 0, 0]);
clicks.forEach((click, i) => {{
    click(); assert.equal(reads[i](), false);
    click(); assert.equal(reads[i](), true);
}});
assert.deepEqual(calls, [2, 2, 2, 2]);
"""], check=True)

with tempfile.TemporaryDirectory(prefix="ii-waffle-toggle-") as tmp:
    root = Path(tmp)
    # Keep the actual event wiring, layout and checked alias; stub only visuals.
    isolated = re.sub(r"^import (?:qs|Quickshell).*\n", "", row, flags=re.M)
    isolated = isolated.replace("Looks.font.pixelSize.large", "16").replace("Looks.colors.subfg", '"gray"')
    isolated = isolated.replace('Translation.tr("On")', '"On"').replace('Translation.tr("Off")', '"Off"')
    isolated = isolated.replace("id: switchWidget", 'id: switchWidget; objectName: "switch"')
    isolated = isolated.replace("MouseArea {", 'MouseArea {\n        objectName: "area"')
    (root / "ToggleItem.qml").write_text(isolated)
    for name, content in {
        "WText": "import QtQuick\nText {}",
        "WTextWithFixedWidth": "import QtQuick\nText { property string longestText }",
        "WSwitch": "import QtQuick.Controls\nSwitch {}",
        "FluentIcon": "import QtQuick\nItem { property string icon; property int implicitSize }",
    }.items():
        (root / f"{name}.qml").write_text(content)
    (root / "tst_toggle.qml").write_text('''import QtQuick
import QtTest
TestCase {
    id: test
    name: "WaffleToggle"
    when: windowShown
    width: 400; height: 120
    visible: true
    property bool sourceChecked: false
    property int clicks: 0
    ToggleItem {
        id: row
        width: 360; height: 64
        name: "Night light"
        checked: test.sourceChecked
        onClicked: { test.clicks++; test.sourceChecked = !test.sourceChecked }
    }
    function test_bindingAndInput() {
        wait(50)
        const sw = findChild(row, "switch")
        const area = findChild(row, "area")
        verify(sw !== null && area !== null)
        sourceChecked = true
        compare(row.checked, true)
        compare(clicks, 0)
        mouseClick(sw, sw.width / 2, sw.height / 2)
        compare(clicks, 1)
        compare(row.checked, false)
        sourceChecked = true
        compare(row.checked, true)
        compare(clicks, 1)
        mouseClick(area, 2, area.height / 2)
        compare(clicks, 2)
        compare(row.checked, false)
        sourceChecked = true
        compare(row.checked, true)
        compare(clicks, 2)
        sw.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(clicks, 3)
        compare(row.checked, false)
        sourceChecked = true
        compare(row.checked, true)
    }
}
''')
    runner = "/usr/lib/qt6/bin/qmltestrunner" if Path("/usr/lib/qt6/bin/qmltestrunner").exists() else "qmltestrunner"
    result = subprocess.run([runner, "-platform", "offscreen", "-input", str(root)],
                            capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, result.stdout + result.stderr
    print(result.stdout.strip())
print("ok: four service actions, external state changes, and both Qt click paths")
