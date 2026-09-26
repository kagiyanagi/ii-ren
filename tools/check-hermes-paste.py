#!/usr/bin/env python3
"""Ctrl+V in the Hermes composer attaches the image that was copied, or pastes text.

The composer decides from cliphist that an image was copied, and used to hand
the attach to the gateway's clipboard.paste, which reads only the live Wayland
selection. That selection dies with the app that offered it, so an image copied
from a window that had since closed failed with "No image found in clipboard"
while cliphist still held it. scripts/hermes/clipboard-image.sh reads it in the
shell instead. This runs it against a fake wl-paste and cliphist for every case:
a live image wins, a live *text* selection is handed back as text (never swapped
for an older image), and only an empty selection falls back to cliphist.
"""
import os
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
SCRIPT = ROOT / "scripts/hermes/clipboard-image.sh"


def run(types, live=b"", listed="", stored=b"", binary="cliphist"):
    with tempfile.TemporaryDirectory() as tmp:
        t = Path(tmp)
        (t / "bin").mkdir()
        (t / "live").write_bytes(live)
        (t / "stored").write_bytes(stored)
        (t / "bin/wl-paste").write_text(
            "#!/bin/bash\n"
            f"[[ $1 == --list-types ]] && {{ printf {types!r}; exit; }}\n"
            f"cat {t}/live\n")
        (t / f"bin/{binary}").write_text(
            "#!/bin/bash\n"
            f"[[ $1 == list ]] && {{ printf {listed!r}'\\n'; exit; }}\n"
            # stash takes the id as an argument; classic cliphist reads the line.
            + ('[[ $1 == decode && $2 == "${LISTED%%$\'\\t\'*}" ]] || exit 1\n' if binary == "stash" else "")
            + f"[[ $1 == decode ]] && cat {t}/stored\n")
        for f in (t / "bin").iterdir():
            f.chmod(0o755)
        env = dict(os.environ, PATH=f"{t}/bin:{os.environ['PATH']}", LISTED=listed)
        out = subprocess.run([str(SCRIPT), str(t / "out"), binary], env=env,
                             capture_output=True, text=True, check=True).stdout.strip()
        body = Path(out).read_bytes() if out.startswith("/") else None
        return out, body


PNG, OLD = b"\x89PNG live", b"\x89PNG stored"
IMAGE_LINE = "5950\t[[ binary data 46 KiB png 431x655 ]]"

out, body = run("image/png\ntext/html\n", live=PNG, listed=IMAGE_LINE, stored=OLD)
assert out.endswith(".png") and body == PNG, f"a live image must win over cliphist, got {out!r}"

out, body = run("image/jpeg\n", live=PNG)
assert out.endswith(".jpg"), f"a jpeg is saved as .jpg, or image.attach refuses the suffix: {out!r}"

out, _ = run("text/plain;charset=utf-8\nUTF8_STRING\n", listed=IMAGE_LINE, stored=OLD)
assert out == "text", f"a text selection must paste as text, not attach cliphist's older image: {out!r}"

out, body = run("", listed=IMAGE_LINE, stored=OLD)
assert out.endswith(".png") and body == OLD, \
    f"an emptied selection (the copying app closed) must fall back to cliphist: {out!r}"

out, body = run("", listed=IMAGE_LINE, stored=OLD, binary="stash")
assert body == OLD, "stash decodes by id, the way Cliphist.decodeCommand calls it"

URIS = b"file:///tmp/a%20b.txt\r\nfile:///tmp/c.py\r\nhttps://example.com/x\r\n"
out, _ = run("text/uri-list\nimage/png\n", live=URIS, listed="5952\tfile:///tmp/a%20b.txt file:///tm")
assert out == "file:///tmp/a%20b.txt\nfile:///tmp/c.py", \
    f"copied files must come back whole from the live selection, local ones only: {out!r}"
out, body = run("text/uri-list\nimage/png\n", live=PNG)
assert out != "" and not out.startswith("file://"), f"a uri-list with no local file falls through to the image: {out!r}"

out, _ = run("", listed="5951\tsome copied text")
assert out == "", f"nothing to attach must print nothing: {out!r}"

service = (ROOT / "services/HermesService.qml").read_text()
assert '"clipboard.paste"' not in service, \
    "HermesService: the attach goes through the gateway's live-only clipboard.paste again"
hermes = (ROOT / "modules/ii/sidebarPolicies/Hermes.qml").read_text()
assert re.search(r"attachClipboardImage\(\(\) => messageInputField\.paste\(\)\)", hermes), \
    "Hermes.qml: a text selection under an image cliphist entry no longer pastes as text"

print("ok: Ctrl+V attaches the copied image from the live clipboard or cliphist, and pastes text as text")
