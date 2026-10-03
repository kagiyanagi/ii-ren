#!/usr/bin/env python3
"""A video wallpaper is decoded once, and the desktop never blinks over a handover.

mpvpaper draws a video wallpaper on its own layer under the shell's. When wallpaper
effects, weather or subject depth are on, the shell plays the video itself, covering
mpvpaper completely - and mpvpaper went on decoding and drawing the same video for
nobody, ~9% of the video engine and a core's tenth of CPU. Only subject depth used
to stand it down, from a singleton the settings app also runs.

Background.qml now owns the handover, and the order is what keeps the screen whole,
measured frame by frame at 60fps: mpvpaper stands down only under a copy that is
playing (a frame has arrived, not just the state) and fully faded in; it comes back
while ours plays on, and ours fades out over it only after its layer has mapped.
Cutting either way showed the empty compositor for 6 to 38 frames.

Also: `pkill -f mpvpaper` killed anything whose command line held the word (an editor,
a terminal); every kill is by exact process name now.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
II = ROOT / "dots/.config/quickshell/ii"
bg = (II / "modules/ii/background/Background.qml").read_text()
subject = (II / "services/WallpaperSubject.qml").read_text()
switchwall = (II / "scripts/colors/switchwall.sh").read_text()

assert "mpvpaper" not in re.sub(r"//[^\n]*", "", subject), \
    "WallpaperSubject.qml handles mpvpaper again; Background.qml is the one owner"

m = re.search(r"function syncMpvpaper\(\) \{\n(.*?)\n        \}\n", bg, re.S)
assert m, "Background.qml: no syncMpvpaper()"
sync = m.group(1)
assert re.search(r"if \(!bgRoot\.shellPlaysVideo \|\| !bgRoot\.videoCopyOpaque\)\s*return;", sync), \
    "mpvpaper must stand down only under our copy, playing and fully opaque"
assert "videoHandoverSettled" in sync, "the handover must wait out the lock and its blur"

assert re.search(r"readonly property bool playing: [^\n]*&& vidOutput\.hasFrame", bg), \
    "`playing` must mean a frame has arrived, not just PlayingState"
assert re.search(r'event\.name !== "openlayer" \|\| event\.data !== "mpvpaper"', bg), \
    "mpvpaper's return (and an outside restart) is read from its openlayer event"
assert re.search(r"onOpacityChanged: \{\s*if \(opacity > 0 \|\| !bgRoot\.videoCopyLeaving\)", bg), \
    "the hold must end when our copy has faded out, not when it starts to"
assert re.search(r"\|\| bgRoot\.mpvpaperDown\)\)\s*\n\s*return \"file://\"", bg), \
    "the player must keep its source while mpvpaper is down, or ours stops before it returns"

for name, text in (("Background.qml", bg), ("switchwall.sh", switchwall)):
    for kill in re.findall(r"pkill[^\n]*mpvpaper", text):
        assert "-f" not in kill.split(), f"{name}: `{kill.strip()}` matches command lines, not the process"

print("ok: one mpvpaper owner, handover under an opaque playing copy, exact-name kills")
