#!/usr/bin/env python3
"""At-a-glance file drops use real send APIs and acknowledge handled drops.

LocalSend.sendFiles never existed. Queue the files in its send card, or share
each file through KDE Connect when LocalSend is unavailable. Run the actual
drop handler under node so a missing method, bad URL conversion or unreachable
fallback cannot silently turn dropping files into a no-op again.
"""
import re
import subprocess
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
widget = (II / "modules/ii/background/widgets/utility/AtAGlanceWidget.qml").read_text()
body = re.search(r"    function handleDroppedFiles\(urls\) \{(.*?)\n    \}", widget, re.S)
assert body
assert "if (root.handleDroppedFiles(drop.urls)) drop.accept(Qt.CopyAction)" in widget
for name, method in (("LocalSend", "addDroppedFile"), ("KdeConnectService", "shareFile")):
    assert f"function {method}(" in (II / f"services/{name}.qml").read_text()
subprocess.run(["node", "-e", "function handleDroppedFiles(urls) {" + body[1] + "}" + r'''
const assert = require('node:assert/strict');
const queued = [], shared = [];
const LocalSend = { available: true, addDroppedFile: p => queued.push(p) };
const KdeConnectService = {
    available: true, activeDevice: { id: 'phone' }, activeDeviceId: 'phone',
    shareFile: (id, path) => shared.push([id, path])
};
const urls = ['file:///tmp/a%20file.txt', 'file:///tmp/100%25.png', '/tmp/raw%.txt'];
const paths = ['/tmp/a file.txt', '/tmp/100%.png', '/tmp/raw%.txt'];
assert.equal(handleDroppedFiles(urls), true);
assert.deepEqual(queued, paths);
assert.deepEqual(shared, []);
LocalSend.available = false;
assert.equal(handleDroppedFiles(urls), true);
assert.deepEqual(shared, paths.map(p => ['phone', p]));
assert.deepEqual(queued, paths);
KdeConnectService.available = false;
assert.equal(handleDroppedFiles(urls), false);
KdeConnectService.available = true;
KdeConnectService.activeDevice = null;
assert.equal(handleDroppedFiles(urls), false);
assert.equal(handleDroppedFiles([]), false);
assert.equal(handleDroppedFiles(['https://example.org/file']), false);
assert.equal(shared.length, paths.length);
'''], check=True)
print("ok: dropped files queue in LocalSend or share via KDE Connect; handled drops are accepted")
