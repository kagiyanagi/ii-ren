"""Loopback round-trip: receive server + send client, accept and deny."""
import json, os, shutil, subprocess, sys, tempfile, threading, time

HELPER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "localsend.py")


def run(answer, payload=b"hello localsend\n", client=None):
    out = tempfile.mkdtemp()
    src = os.path.join(tempfile.mkdtemp(), "note it.txt")
    open(src, "wb").write(payload)
    srv = subprocess.Popen([sys.executable, HELPER, "receive", "--output", out],
                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    events = []

    def reader():
        for line in srv.stdout:
            ev = json.loads(line)
            events.append(ev)
            if ev.get("event") == "prompt":
                srv.stdin.write(answer + "\n"); srv.stdin.flush()

    threading.Thread(target=reader, daemon=True).start()
    for _ in range(50):
        if any(e.get("event") == "ready" for e in events):
            break
        time.sleep(0.1)
    assert any(e.get("event") == "ready" for e in events), events
    send = client(src) if client else subprocess.run(
        [sys.executable, HELPER, "send", "127.0.0.1", src], capture_output=True, text=True)
    time.sleep(0.5)
    srv.terminate(); srv.wait(5)
    sent = [json.loads(l) for l in send.stdout.splitlines()]
    files = os.listdir(out)
    shutil.rmtree(out, ignore_errors=True)
    return events, sent, files


ev, sent, files = run("y")
kinds = [e.get("event") for e in ev]
assert "incoming" in kinds and "prompt" in kinds, ev
inc = next(e for e in ev if e["event"] == "incoming")
assert inc["files"] == [{"name": "note it.txt", "size": 16}], inc
assert [e.get("event") for e in sent][-1] == "completed", sent
assert files == ["note it.txt"], files
print("accept ok:", kinds, "->", files)

ev, sent, files = run("n")
assert "cancelled" in [e.get("event") for e in ev], ev
assert files == [], files
assert sent and sent[-1].get("error") == "declined by receiver", sent
print("deny ok:", [e.get("event") for e in ev])

ev, sent, files = run("y", b"x" * (700 * 1024))
saved = next(e for e in ev if e.get("event") == "saved")
assert saved["size"] == 700 * 1024, saved
print("large ok:", saved["size"], "bytes")


def app_upload(src):
    """Upload the way the LocalSend app does: chunked, no Content-Length."""
    import http.client
    data = open(src, "rb").read()
    files = {"f": {"id": "f", "fileName": "photo.jpg", "size": len(data), "fileType": "image/jpeg"}}
    c = http.client.HTTPConnection("127.0.0.1", 53317, timeout=10)
    c.request("POST", "/api/localsend/v2/prepare-upload", json.dumps({"info": {"alias": "phone"}, "files": files}),
              {"Content-Type": "application/json"})
    prep = json.loads(c.getresponse().read())
    c.request("POST", f"/api/localsend/v2/upload?sessionId={prep['sessionId']}&fileId=f&token={prep['files']['f']}",
              iter([data[:1000], data[1000:]]), encode_chunked=True)
    c.getresponse().read()
    return subprocess.CompletedProcess([], 0, "", "")


ev, sent, files = run("y", b"y" * (300 * 1024), client=app_upload)
saved = next(e for e in ev if e.get("event") == "saved")
assert saved["size"] == 300 * 1024, saved
assert files == ["photo.jpg"] and saved["path"].endswith("photo.jpg"), (files, saved)
print("chunked ok:", saved["size"], "bytes")
print("PASS")
