#!/usr/bin/env python3
"""Assert an unset `media.priorityPlayer` hands the media controls to no player.

MprisController re-picks the priority player every time a player appears or goes
away, by comparing the setting with each player's DesktopEntry. The setting defaults
to "", and a player that sends no DesktopEntry reads as "" too -- Chromium-based
browsers send none. So out of the box the browser was "the priority player": every
player that came or went threw the controls back to it, away from whatever the user
was listening to (seen 2026-11-10). It looks like the shell preferring whatever is
playing, so it is checked here rather than by opening and closing players.

This runs the real isPriorityPlayer and onAllPlayersChanged from the QML under node.

Run: python3 tools/check-mpris-priority-player.py
"""
import json
import pathlib
import re
import subprocess

SRC = (pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii/services/MprisController.qml").read_text()


def block(start: int) -> tuple[int, int]:
    """The brace-balanced `{...}` that opens at or after `start`, as (open, close+1)."""
    i = SRC.index("{", start)
    depth = 0
    for j in range(i, len(SRC)):
        depth += {"{": 1, "}": -1}.get(SRC[j], 0)
        if depth == 0:
            return i, j + 1
    raise AssertionError("unbalanced braces in MprisController.qml")


def function(name: str) -> str:
    """The QML function `name` as plain JS, with its type annotations stripped."""
    start = SRC.index(f"function {name}(")
    i, j = block(start)
    head = re.sub(r"(\w+): \w+", r"\1", SRC[start:i].replace(f"function {name}", "", 1))
    head = re.sub(r"\)\s*:\s*\w+\s*$", ")", head.strip())
    return f"root.{name} = function{head} {SRC[i:j]};"


assert "onAllPlayersChanged: {" in SRC, "MprisController no longer re-picks a player on onAllPlayersChanged"
i, j = block(SRC.index("onAllPlayersChanged: {"))
handler = SRC[i:j]

# Chromium sends no DesktopEntry at all; QML reads that as "". Both spellings are tried.
CHROMIUM = {"dbusName": "org.mpris.MediaPlayer2.chromium.instance190133", "desktopEntry": ""}
NO_ENTRY = {"dbusName": "org.mpris.MediaPlayer2.helium.instance7"}
MPV = {"dbusName": "org.mpris.MediaPlayer2.mpv", "desktopEntry": "mpv"}
SPOTIFY = {"dbusName": "org.mpris.MediaPlayer2.spotify", "desktopEntry": "spotify"}

CASES = [
    # (setting, players on the bus, tracked before, tracked after, why)
    ("", [CHROMIUM, MPV], MPV, MPV, "an unset priority gave the controls to a player with an empty DesktopEntry"),
    ("", [NO_ENTRY, MPV], MPV, MPV, "an unset priority gave the controls to a player with no DesktopEntry"),
    ("", [MPV, CHROMIUM], None, None, "an unset priority picked a player when nothing was tracked"),
    ("spotify", [CHROMIUM, NO_ENTRY, MPV], MPV, MPV, "a priority that is not on the bus moved the controls"),
    ("spotify", [CHROMIUM, SPOTIFY, MPV], MPV, SPOTIFY, "a priority player on the bus no longer takes the controls"),
]

script = "const root = {};\n" + function("isPriorityPlayer") + "\n" + f"""
root.onAllPlayersChanged = function () {{ with (root) {handler} }};
const cases = {json.dumps([[s, p, b, a] for s, p, b, a, _ in CASES])};
const out = cases.map(([setting, players, before]) => {{
    Object.assign(root, {{ priorityPlayer: setting, allPlayers: players, pageUrlTracks: {{}} }});
    root.trackedPlayer = before === null ? null : players.find(p => p.dbusName === before.dbusName);
    root.onAllPlayersChanged();
    return root.trackedPlayer?.dbusName ?? null;
}});
const lone = [null, undefined, {{}}, {{ desktopEntry: "" }}].flatMap(p =>
    ["", "spotify"].map(setting => (root.priorityPlayer = setting, root.isPriorityPlayer(p))));
console.log(JSON.stringify({{ out, lone }}));
"""

result = json.loads(subprocess.run(["node", "-e", script], capture_output=True, text=True, check=True).stdout)

for (setting, _, _, after, why), got in zip(CASES, result["out"]):
    want = after and after["dbusName"]
    assert got == want, f"priorityPlayer={setting!r}: {why} (tracked {got}, want {want})"
assert not any(result["lone"]), \
    "isPriorityPlayer matched a missing player or an empty DesktopEntry: " + json.dumps(result["lone"])

print(f"ok: {len(CASES)} player changes, an unset priority never takes the controls")
