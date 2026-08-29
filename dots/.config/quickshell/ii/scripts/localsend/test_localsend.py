"""Loopback round-trip: receive server + send client, accept and deny."""
import json, os, shutil, subprocess, sys, tempfile, threading, time

HELPER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "localsend.py")


def run(answer, payload=b"hello localsend\n"):
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
    send = subprocess.run([sys.executable, HELPER, "send", "127.0.0.1", src],
                          capture_output=True, text=True)
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
print("chunked ok:", saved["size"], "bytes")
print("PASS")
