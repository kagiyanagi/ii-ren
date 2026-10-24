#!/usr/bin/env python3
"""Cover art is fetched in one place, with the url passed as an argument.

A browser hands a web page's mediaSession artwork url to MPRIS unchanged, and a url
path may hold `'` and `$(`. Thirteen widgets each pasted that url into a
`bash -c "curl '<url>'"` string, so any page playing media could run commands.
They also raced each other on one shared .tmp file. Now services/CoverArt.qml is
the only fetcher, and its shell script reads the urls as arguments.

It takes more than one: YouTube's 1280x720 frame is missing on uploads below 720p,
so the 320x180 one follows it. This runs the script against a hostile url and a
file:// url and asserts neither gets anywhere, then against a local server to
assert a missing first url falls through to the next.
"""
import http.server
import re
import subprocess
import tempfile
import threading
from functools import partial
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
service = (II / "services/CoverArt.qml").read_text()

for f in II.rglob("*.qml"):
    if f.name == "CoverArt.qml" or "/waffle/" in str(f):
        continue
    t = f.read_text(errors="ignore")
    rel = f.relative_to(II)
    assert "Directories.coverArt" not in t, f"{rel}: downloads cover art itself; use CoverArt.source()"
    assert not re.search(r"curl[^\n]*\$\{[^}]*artUrl", t), f"{rel}: interpolates an art url into curl"

m = re.search(r'command: \["sh", "-c", \'(.+?)\',\s*"sh", path\]\.concat\(urls\)', service, re.S)
assert m, "CoverArt.qml: fetch command is no longer sh -c '<script>' sh path urls..."
script = m.group(1)
assert "${" not in script.replace("${1%/*}", ""), "CoverArt.qml: fetch script interpolates a value"
assert "--proto =http,https" in script, "CoverArt.qml: curl may follow non-http schemes"

with tempfile.TemporaryDirectory() as d:
    hostile = f"https://x.invalid/a'$(touch${{IFS}}{d}/pwned)'"
    subprocess.run(["sh", "-c", script, "sh", f"{d}/a", hostile], capture_output=True, timeout=30)
    assert not Path(d, "pwned").exists(), "CoverArt.qml: a url ran a command"
    r = subprocess.run(["sh", "-c", script, "sh", f"{d}/b", "file:///etc/hostname"], capture_output=True, timeout=30)
    assert r.returncode != 0 and not Path(d, "b").exists(), "CoverArt.qml: fetched a file:// url"
    r = subprocess.run(["sh", "-c", script, "sh", f"{d}/c", "file:///etc/hostname", hostile], capture_output=True, timeout=30)
    assert r.returncode != 0 and not Path(d, "c").exists(), "CoverArt.qml: a fallback url got somewhere"
    assert not Path(d, "pwned").exists(), "CoverArt.qml: a fallback url ran a command"

    Path(d, "frame.jpg").write_bytes(b"art")
    class Quiet(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass
    server = http.server.HTTPServer(("127.0.0.1", 0), partial(Quiet, directory=d))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_port}"
    r = subprocess.run(["sh", "-c", script, "sh", f"{d}/out/e", f"{base}/missing.jpg", f"{base}/frame.jpg"], capture_output=True, timeout=30)
    server.shutdown()
    assert r.returncode == 0 and Path(d, "out/e").read_bytes() == b"art", "CoverArt.qml: a missing url did not fall through to the next"

print("ok: cover art has one fetcher, a url cannot run a command or read a local file, and a missing one falls through")
