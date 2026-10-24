#!/usr/bin/env python3
"""Assert MprisController.artUrlFor never names a video the track has moved on from.

YouTube's art comes from its own 1280x720 frame, found through the video id in the
player's page url (xesam:url), because the browser only passes on a 336x188 thumbnail.
But plasma-browser-integration sends that url only with its "playing" message
(extension-mpris.js: `payload.url = sender.tab.url`). A song that changes inside the
page -- autoplay, a playlist, YouTube's next button -- arrives as metadata alone, with
the previous video's url still on it. Every media surface then kept the old song's art
(or none) until a pause and play sent the url again (seen 2026-10-24: a song's art
fetched 23 minutes after it started, at the pause).

This runs the real artUrlFor/notePageUrl from the QML under node through those message
sequences. Each update is checked both before and after the metadata handler has run,
since a binding may re-evaluate on either side of it.

Run: python3 tools/check-mpris-art-url.py
"""
import json
import pathlib
import re
import subprocess

SRC = (pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii/services/MprisController.qml").read_text()


def function(name: str) -> str:
    """The QML function `name`, brace-balanced, with its type annotations stripped."""
    start = SRC.index(f"function {name}(")
    i = SRC.index("{", start)
    depth = 0
    for j in range(i, len(SRC)):
        depth += {"{": 1, "}": -1}.get(SRC[j], 0)
        if depth == 0:
            break
    head, body = SRC[start:i], SRC[i:j + 1]
    head = re.sub(r"(\w+): \w+", r"\1", head.replace(f"function {name}", "", 1))
    head = re.sub(r"\)\s*:\s*\w+\s*$", ")", head.strip())
    return f"root.{name} = function{head} {body};"


script = "const root = { pageUrlTracks: {} };\n" + "\n".join(
    function(name) for name in ("artUrlFor", "trackKeyOf", "notePageUrl")) + r"""
const player = { dbusName: "org.mpris.MediaPlayer2.plasma-browser-integration", trackArtUrl: "", metadata: {} };
const out = [];
function update(metadata, art) {
    player.metadata = metadata;
    player.trackArtUrl = art;
    const before = root.artUrlFor(player);
    root.notePageUrl(player, false);
    out.push([before, root.artUrlFor(player)]);
}
const watch = id => `https://www.youtube.com/watch?v=${id}&list=PL1`;

root.notePageUrl(player, true);                                                    // shell starts, nothing playing
update({ "xesam:url": watch("aaaaaaaaaaa"), "xesam:title": "A", "xesam:artist": ["x"] }, "file:///tmp/a.jpg");  // 0 "playing"
update({ "xesam:url": watch("aaaaaaaaaaa"), "xesam:title": "B", "xesam:artist": ["y"] }, "file:///tmp/b.jpg");  // 1 in-page song change
update({ "xesam:url": watch("bbbbbbbbbbb"), "xesam:title": "B", "xesam:artist": ["y"] }, "file:///tmp/b2.jpg"); // 2 pause + play
update({ "xesam:url": watch("bbbbbbbbbbb"), "xesam:title": "B", "xesam:artist": ["y"] }, "file:///tmp/b3.jpg"); // 3 art re-sent, same track
update({ "xesam:url": watch("bbbbbbbbbbb"), "xesam:title": "C", "xesam:artist": ["z"] }, "");                   // 4 song change, art not here yet
update({ "xesam:url": "https://music.youtube.com/watch?v=ccccccccccc", "xesam:title": "D", "xesam:artist": ["w"] }, "file:///tmp/d.jpg"); // 5 YouTube Music
update({ "xesam:title": "E", "xesam:artist": ["v"] }, "file:///tmp/e.jpg");                                     // 6 not a web page
console.log(JSON.stringify(out));
"""

result = subprocess.run(["node", "-e", script], capture_output=True, text=True, timeout=30)
assert result.returncode == 0, f"artUrlFor did not run under node:\n{result.stderr}"
steps = json.loads(result.stdout)

hq = lambda vid: f"https://i.ytimg.com/vi/{vid}/hq720.jpg"
EXPECTED = [
    (hq("aaaaaaaaaaa"), "a song that starts playing gets its video's 1280x720 frame"),
    ("file:///tmp/b.jpg", "a song changed inside the page must keep the browser's art, not the last video's frame"),
    (hq("bbbbbbbbbbb"), "once the url catches up, the new video's frame comes back"),
    (hq("bbbbbbbbbbb"), "art re-sent for the same track must not drop the frame"),
    (hq("bbbbbbbbbbb"), "with no art of its own yet, the page's frame is still the best guess"),
    ("file:///tmp/d.jpg", "YouTube Music keeps its square album cover"),
    ("file:///tmp/e.jpg", "a player with no page url keeps its own art"),
]
for i, ((before, after), (want, why)) in enumerate(zip(steps, EXPECTED)):
    assert before == want and after == want, f"step {i}: {why}\n  got {before!r} / {after!r}, want {want!r}"

print(f"ok: {len(EXPECTED)} message sequences resolve to the current track's art")
