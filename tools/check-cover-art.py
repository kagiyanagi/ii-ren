#!/usr/bin/env python3
"""Cover art is fetched in one place, with the url passed as an argument.

A browser hands a web page's mediaSession artwork url to MPRIS unchanged, and a url
path may hold `'` and `$(`. Thirteen widgets each pasted that url into a
`bash -c "curl '<url>'"` string, so any page playing media could run commands.
They also raced each other on one shared .tmp file. Now services/CoverArt.qml is
the only fetcher, and its shell script reads the url as "$2".

This runs that script against a hostile url and a file:// url and asserts neither
gets anywhere.
"""
import re
import subprocess
import tempfile
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

m = re.search(r'command: \["sh", "-c", \'(.+?)\',\s*"sh", path, url\]', service, re.S)
assert m, "CoverArt.qml: fetch command is no longer sh -c '<script>' sh path url"
script = m.group(1)
assert "${" not in script.replace("${1%/*}", ""), "CoverArt.qml: fetch script interpolates a value"
assert "--proto =http,https" in script, "CoverArt.qml: curl may follow non-http schemes"

with tempfile.TemporaryDirectory() as d:
    hostile = f"https://x.invalid/a'$(touch${{IFS}}{d}/pwned)'"
    subprocess.run(["sh", "-c", script, "sh", f"{d}/a", hostile], capture_output=True, timeout=30)
    assert not Path(d, "pwned").exists(), "CoverArt.qml: a url ran a command"
    r = subprocess.run(["sh", "-c", script, "sh", f"{d}/b", "file:///etc/hostname"], capture_output=True, timeout=30)
    assert r.returncode != 0 and not Path(d, "b").exists(), "CoverArt.qml: fetched a file:// url"

print("ok: cover art has one fetcher, and a url cannot run a command or read a local file")
