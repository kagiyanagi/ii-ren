#!/usr/bin/env python3
"""Settings launchers reuse one window and deliver every navigation request.

Race several real launcher processes against a fake qs that starts slowly. Only
one app may start, and subsequent page/highlight requests must reach its IPC.
Also guard every QML entry point so a new direct qs launch cannot bypass reuse.
The real settings app is exercised separately by smoke-settings.sh.
"""
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
launcher = II / "scripts/settings/open.py"
assert launcher.exists(), "no shared settings launcher"
for path in II.rglob("*.qml"):
    source = path.read_text()
    assert not re.search(r'execDetached\([^\n]*(?:shellPath\("settings.qml"\)|settingsQmlPath)', source), \
        f"{path.relative_to(II)}: starts a second settings window directly"
settings = (II / "settings.qml").read_text()
assert 'target: "settings"' in settings and "root.present(page, highlight)" in settings
assert "onLoaded: root.deliverNavigation()" in settings
service = (II / "services/SettingsLauncher.qml").read_text()
opener = re.search(r"    function open\([^\n]*\) \{\n(.*?)\n    \}", service, re.S).group(1)
subprocess.run(["node", "-e", """
const assert = require('assert/strict');
const focused = [], restored = [], calls = [];
const HyprlandData = {windowList: [{title:'illogical-impulse Settings',address:'0x1',focusHistoryID:2}]};
let minimized = false;
const FloatingMode = {restoreMinimized: address => (restored.push(address), minimized), focus: address => focused.push(address)};
const Quickshell = {shellPath: p => p, execDetached: c => calls.push(c)};
const open = (page = '', highlight = '') => {
""" + opener + """
};
open('battery');
assert.deepEqual(focused, ['0x1'], 'an existing settings window was not brought forward');
minimized = true;
open('agent');
assert.deepEqual(restored, ['0x1','0x1'], 'minimized settings were not restored');
assert.equal(focused.length, 1);
assert.deepEqual(calls.map(c => c.slice(-2)), [['battery',''],['agent','']]);
"""], check=True)

functions = []
for name in ("present", "deliverNavigation"):
    match = re.search(rf"    function {name}\([^\n]*\) \{{\n.*?\n    \}}", settings, re.S)
    assert match, f"missing {name}"
    functions.append(match.group().replace(f"function {name}", f"root.{name} = function", 1))
subprocess.run(["node", "-e", """
const assert = require('assert/strict');
const Loader = {Ready: 1}, searchInput = {text: 'old search'};
const pageLoader = {status: 1, source: 'modules/settings/BatteryConfig.qml'};
const root = {
    pages: [{id:'battery',component:'modules/settings/BatteryConfig.qml'},
            {id:'widgets',component:'modules/settings/WidgetsConfig.qml'}],
    currentPage: 0, pendingNavigation: null,
    pageIndexById(id) {return this.pages.findIndex(p => p.id === id)},
    openPage(i) {this.currentPage = i}, showNormal() {}, raise() {}, requestActivate() {}
};
""" + "\n".join(functions) + """
root.present('widgets', 'widgets/ClockConfig.qml');
assert.equal(root.pendingSectionHighlight, '', 'old page consumed a new page highlight');
assert(root.pendingNavigation);
pageLoader.source = 'modules/settings/WidgetsConfig.qml'; // Loader.source stays relative in Quickshell.
root.deliverNavigation();
assert.equal(root.pendingSectionHighlight, 'widgets/ClockConfig.qml');
assert.equal(root.pendingNavigation, null);
root.present('widgets', 'widgets/OtherClockConfig.qml');
assert.equal(root.pendingSectionHighlight, 'widgets/OtherClockConfig.qml', 'same-page deep link was lost');
root.present('', '');
assert.equal(root.currentPage, 1, 'generic open changed the current page');
"""], check=True)

with tempfile.TemporaryDirectory(prefix="ii-settings-launch-") as directory:
    path = Path(directory)
    fake = path / "qs"
    fake.write_text('''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
root = Path(os.environ["SETTINGS_CHECK"])
if "ipc" in sys.argv:
    if not (root / "ready").exists(): sys.exit(1)
    assert sys.argv[sys.argv.index("call") + 1:][:2] == ["settings", "open"]
    with (root / "requests").open("a") as log:
        log.write(json.dumps(sys.argv[-2:]) + "\\n")
else:
    assert "--no-duplicate" in sys.argv
    with (root / "starts").open("a") as log: log.write("start\\n")
    time.sleep(.3)
    (root / "ready").touch()
''')
    fake.chmod(0o755)
    env = dict(os.environ, PATH=directory + os.pathsep + os.environ["PATH"],
               XDG_RUNTIME_DIR=directory, SETTINGS_CHECK=directory)
    pages = [("battery", ""), ("agent", ""), ("widgets", "widgets/ClockConfig.qml"), ("", "")]
    processes = [subprocess.Popen(["python3", str(launcher), str(path / "settings.qml"), *args],
                                  env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for args in pages]
    for process in processes:
        output, error = process.communicate(timeout=8)
        assert process.returncode == 0, error.decode() + output.decode()
    assert (path / "starts").read_text().splitlines() == ["start"], "concurrent clicks opened multiple settings apps"
    requests = [json.loads(line) for line in (path / "requests").read_text().splitlines()]
    assert sorted(requests) == sorted(map(list, pages)), f"navigation request lost: {requests}"
print("ok: concurrent settings clicks launch once and deliver every page and highlight")
