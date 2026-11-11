#!/usr/bin/env python3
"""The send card can select files and run a bounded scan, even before helper readiness.

The card called four missing service members, so neither button nor its mount-time
scan worked. Exercise the actual QML methods under node, and the Python discovery
loop with fake packets and a clock: scans terminate, ignore malformed/self packets,
report peers once, and close their socket without stopping the receive server.

Clock drops arrive as file URLs, while the picker and At-a-glance pass filesystem
paths. Exercise those real intake paths so percent escapes are decoded once, not
left in the filename or decoded again. Run a constructed send through the Python
helper against real temporary files and fake HTTP responses; the selected paths
and the peer's advertised port must survive every boundary without network I/O.
"""
import importlib.util
import json
import re
import subprocess
import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
service = (II / "services/LocalSend.qml").read_text()
card = (II / "modules/ii/bar/cards/LocalSendSendCard.qml").read_text()


def method(name):
    match = re.search(rf"    function {name}\((.*?)\)(?:: \w+)? \{{\n(.*?)\n    \}}", service, re.S)
    assert match, f"LocalSend.{name} is missing"
    args = re.sub(r": \w+", "", match[1])
    return f"function {name}({args}) {{\n{match[2]}\n}}"


assert "readonly property bool scanning: scanProc.running" in service
assert 'command: ["python3", root.helperPath, "scan"]' in service
assert "onExited: root._scanRequested = false" in service
assert "this.text.split(" in service and "root.addDroppedFile(p)" in service
for member in ("openFilePicker", "startScanning", "stopScanning"):
    assert f"LocalSend.{member}()" in card
assert "Component.onDestruction" in card and "LocalSend.stopScanning()" in card
ready = re.search(r"onAvailableChanged: (.*)", service)[1]
js = "\n".join(method(name) for name in (
    "openFilePicker", "startScanning", "stopScanning", "addDroppedFile", "sendToDevice", "handleLocalSendEvent"))
subprocess.run(["node", "-e", js + f"""
const assert = require('node:assert/strict');
console.log = () => {{}};
const pickerProc = {{ running: false }};
const scanProc = {{ running: false }};
const sendProc = {{ running: false, command: [] }};
const root = {{ available: false, _scanRequested: false, droppedFiles: [], discoveredDevices: [],
    sending: false, helperPath: '/shell/localsend.py', startScanning, addDroppedFile }};
Object.defineProperty(root, 'scanning', {{ get: () => scanProc.running }});
openFilePicker();
assert.equal(pickerProc.running, true);
startScanning();
assert.equal(scanProc.running, false);
assert.equal(root._scanRequested, true);
root.available = true;
{ready}
assert.equal(scanProc.running, true);
startScanning();
stopScanning();
assert.equal(scanProc.running, false);
assert.equal(root._scanRequested, false);
root.available = false;
startScanning();
stopScanning();
root.available = true;
{ready}
assert.equal(scanProc.running, false);
addDroppedFile('/tmp/a file.txt');
addDroppedFile('/tmp/a file.txt');
addDroppedFile('/tmp/$(literal).png');
assert.deepEqual(root.droppedFiles.map(f => f.path), ['/tmp/a file.txt', '/tmp/$(literal).png']);
""" + r'''
addDroppedFile('file:///tmp/a%20file.txt');
assert.equal(root.droppedFiles.length, 2, 'URL and plain path must name the same file');
addDroppedFile('file:///tmp/%E6%97%A5%E6%9C%AC%E8%AA%9E%25.txt');
addDroppedFile('file:///tmp/literal%2520.txt');
addDroppedFile('/tmp/literal%20.txt');
addDroppedFile('/tmp/raw%.txt');
addDroppedFile('file://localhost/tmp/a%23b%3Fc.txt');
assert.deepEqual(root.droppedFiles.slice(2).map(f => f.path), [
    '/tmp/日本語%.txt', '/tmp/literal%20.txt', '/tmp/raw%.txt', '/tmp/a#b?c.txt'
]);
const validCount = root.droppedFiles.length;
for (const invalid of ['file:///tmp/bad%escape', 'file://remote/tmp/file',
        'https://example.org/file', 'relative.txt', 'file:///tmp/a%00b']) {
    assert.doesNotThrow(() => addDroppedFile(invalid));
}
assert.equal(root.droppedFiles.length, validCount, 'invalid or remote drops entered the send queue');

root.available = true;
handleLocalSendEvent({event:'device', ip:'192.0.2.10', alias:'Phone', port:53318});
sendToDevice('192.0.2.10');
assert.equal(sendProc.command[3], '192.0.2.10:53318', 'custom discovery port was discarded');
assert.equal(root.sending, true);
const firstCommand = sendProc.command;
sendToDevice('192.0.2.10');
assert.equal(sendProc.command, firstCommand, 'a second send started while already sending');
root.sending = false;
handleLocalSendEvent({event:'device', ip:'192.0.2.10', alias:'Phone renamed', port:54321});
assert.equal(root.discoveredDevices.length, 1, 'rescanning duplicated the same peer');
assert.equal(root.discoveredDevices[0].name, 'Phone renamed');
const stableDevices = root.discoveredDevices;
handleLocalSendEvent({event:'device', ip:'192.0.2.10', alias:'Phone renamed', port:54321});
assert.equal(root.discoveredDevices, stableDevices, 'unchanged discovery rebuilt the device rows');
sendToDevice('192.0.2.10');
assert.equal(sendProc.command[3], '192.0.2.10:54321', 'rescan retained an obsolete peer port');
root.sending = false;
handleLocalSendEvent({event:'device', ip:'192.0.2.11', alias:'Default port'});
sendToDevice('192.0.2.11');
assert.equal(sendProc.command[3], '192.0.2.11:53317');
for (const port of [0, -1, 65536, 1.5, '', 'invalid']) {
    root.sending = false;
    sendProc.running = false;
    handleLocalSendEvent({event:'device', ip:'192.0.2.10', port});
    sendToDevice('192.0.2.10');
    assert.equal(sendProc.running, false, 'invalid advertised port started a send: ' + port);
    assert.equal(root.sending, false);
}
for (const ip of ['', '::1', '192.0.2.999', '192.0.2', '192.0.2.10:53318']) {
    root.sending = false;
    sendProc.running = false;
    sendToDevice(ip);
    assert.equal(sendProc.running, false, 'unsupported address started a send: ' + ip);
}
'''], check=True)

# Call the real drop handlers as well as the shared service: At-a-glance already
# decodes the URL, and its literal %20 filename must not be decoded a second time.
drop_handlers = []
for relative in ("modules/ii/bar/ClockWidget.qml", "modules/ii/verticalBar/VerticalClockWidget.qml"):
    source = (II / relative).read_text()
    drop_handlers.append(re.search(r"onDropped: \(drop\) => \{\n(.*?)\n        \}", source, re.S)[1])
glance = (II / "modules/ii/background/widgets/utility/AtAGlanceWidget.qml").read_text()
glance_drop = re.search(r"    function handleDroppedFiles\(urls\) \{(.*?)\n    \}", glance, re.S)[1]
subprocess.run(["node", "-e", method("addDroppedFile") + r'''
const assert = require('node:assert/strict');
const root = {droppedFiles: []};
const LocalSend = {available: true, addDroppedFile};
const Qt = {CopyAction: 1};
const urls = ['file:///tmp/a%20file.txt', 'file:///tmp/literal%2520.txt', 'file:///tmp/%E6%97%A5%25.txt'];
const expected = ['/tmp/a file.txt', '/tmp/literal%20.txt', '/tmp/日%.txt'];
''' + f"""
for (const body of {json.dumps(drop_handlers)}) {{
    root.droppedFiles = [];
    let accepted = false;
    new Function('LocalSend', 'drop', 'Qt', body)(LocalSend, {{urls, hasUrls:true, accept(action) {{
        assert.equal(action, Qt.CopyAction); accepted = true;
    }}}}, Qt);
    assert.equal(accepted, true);
    assert.deepEqual(root.droppedFiles.map(f => f.path), expected);
}}
root.droppedFiles = [];
const KdeConnectService = {{available:false}};
const accepted = new Function('LocalSend', 'KdeConnectService', 'urls', {json.dumps(glance_drop)})(LocalSend, KdeConnectService, urls);
assert.equal(accepted, true);
assert.deepEqual(root.droppedFiles.map(f => f.path), expected, 'At-a-glance paths were decoded twice');
"""], check=True)

spec = importlib.util.spec_from_file_location("localsend", II / "scripts/localsend/localsend.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class Response:
    status = 200

    def __enter__(self): return self
    def __exit__(self, *args): pass
    def close(self): pass
    def read(self):
        return json.dumps(dict(sessionId="test", files={str(i): "token" for i in range(3)})).encode()


with tempfile.TemporaryDirectory(prefix="ii-localsend-paths-") as directory:
    files = [Path(directory) / name for name in ("a file.txt", "日本語%.txt", "literal%20.txt")]
    for index, path in enumerate(files):
        path.write_bytes(f"content {index}".encode())
    command = json.loads(subprocess.run(["node", "-e",
        method("addDroppedFile") + method("sendToDevice") + f"""
const root = {{available:true, sending:false, helperPath:'localsend.py', droppedFiles:[],
    discoveredDevices:[{{ip:'192.0.2.10', port:53318}}]}};
const sendProc = {{running:false}};
for (const url of {json.dumps([path.as_uri() for path in files])}) addDroppedFile(url);
sendToDevice('192.0.2.10');
process.stdout.write(JSON.stringify(sendProc.command));
"""], capture_output=True, text=True, check=True).stdout)
    prepared, uploads, urls = [], [], []

    def post(url, obj=None, data=None, length=None):
        urls.append(url)
        if obj is not None:
            prepared.append(obj)
        else:
            content = data.read()
            assert len(content) == length
            uploads.append(content)
        return Response()

    with patch.object(helper, "post", side_effect=post), patch.object(helper, "emit"):
        assert helper.send(SimpleNamespace(target=command[3], files=command[4:])) == 0
    assert all(url.startswith("https://192.0.2.10:53318/api/localsend/v2/") for url in urls), urls
    assert [meta["fileName"] for meta in prepared[0]["files"].values()] == [path.name for path in files]
    assert uploads == [path.read_bytes() for path in files]


class Socket:
    def __init__(self):
        self.sent = []
        self.closed = False
        self.packets = iter([
            b"bad json", b"[]",
            json.dumps(helper.INFO).encode(),
            json.dumps(dict(fingerprint="phone", alias="Phone", port=53318, announce=True)).encode(),
            json.dumps(dict(fingerprint="phone", alias="Phone", port=53318)).encode(),
        ])

    def setsockopt(self, *args): pass
    def bind(self, address): assert address == ("", helper.PORT)
    def settimeout(self, timeout): assert 0 < timeout <= 1
    def sendto(self, message, address): self.sent.append((json.loads(message), address))
    def recvfrom(self, size):
        try:
            return next(self.packets), ("192.0.2.10", helper.PORT)
        except StopIteration:
            raise helper.socket.timeout()
    def close(self): self.closed = True


sock = Socket()
events = []
clock = iter(n / 10 for n in range(100))
with patch.object(helper.socket, "socket", return_value=sock), \
     patch.object(helper.time, "monotonic", side_effect=lambda: next(clock)), \
     patch.object(helper, "emit", side_effect=lambda **event: events.append(event)):
    helper.discovery(timeout=3)
assert sock.closed
assert events == [dict(event="device", alias="Phone", ip="192.0.2.10", port=53318)], events
assert sock.sent[0][0]["announce"] is True
assert any(packet[0]["announce"] is False for packet in sock.sent)
print("ok: picker, scans, decoded drop paths, refreshed discovery ports and helper sends retain filenames and destination")
