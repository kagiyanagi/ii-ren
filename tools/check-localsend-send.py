#!/usr/bin/env python3
"""The send card can select files and run a bounded scan, even before helper readiness.

The card called four missing service members, so neither button nor its mount-time
scan worked. Exercise the actual QML methods under node, and the Python discovery
loop with fake packets and a clock: scans terminate, ignore malformed/self packets,
report peers once, and close their socket without stopping the receive server.
"""
import importlib.util
import json
import re
import subprocess
from pathlib import Path
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
    "openFilePicker", "startScanning", "stopScanning", "addDroppedFile"))
subprocess.run(["node", "-e", js + f"""
const assert = require('node:assert/strict');
const pickerProc = {{ running: false }};
const scanProc = {{ running: false }};
const root = {{ available: false, _scanRequested: false, droppedFiles: [], startScanning }};
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
"""], check=True)

spec = importlib.util.spec_from_file_location("localsend", II / "scripts/localsend/localsend.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


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
print("ok: picker, deferred/cancelled scans, bounded discovery and peer events")
