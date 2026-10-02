#!/usr/bin/env python3
"""Config profiles never lose the live config.

scripts/profiles/profiles.sh swaps config.json under the running shell, so its
failures are lost settings rather than a wrong frame. This runs it against a
temp dir and checks four things. A switch saves the live
config into the active profile before it loads the next one, so edits made
since the last switch survive. A switch to a missing profile leaves the live
config alone, because `cat missing > config` truncates it first. Only the
active profile can't be deleted. Listing writes nothing, since the page lists
on open (TASTE.md 3.2).
"""
import json, pathlib, subprocess, tempfile

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/scripts/profiles/profiles.sh"

t = pathlib.Path(tempfile.mkdtemp())
D, C = t / "profiles", t / "config.json"


def run(*args):
    p = subprocess.run(["sh", str(SCRIPT), str(D), str(C), *args], capture_output=True, text=True)
    active, wall, *names = p.stdout.split("\n")
    return p.returncode, active, wall, [n for n in names if n]


def cfg(wall):
    return json.dumps({"background": {"wallpaperPath": wall}})


C.write_text(cfg("/a.png"))

assert run("list") == (0, "Default", "", []), run("list")
assert not D.exists(), "listing created the profiles dir"

assert run("new", "Work")[:2] == (0, "Work")
assert (D / "Default.json").read_text() == (D / "Work.json").read_text() == cfg("/a.png")
assert run("new", "Work")[0] != 0, "new overwrote an existing profile"

# Edits made in Work, then a switch: they are saved into Work, Default comes back.
C.write_text(cfg("/b.png"))
code, active, wall, names = run("switch", "Default")
assert (code, active, wall, names) == (0, "Default", "/a.png", ["Default", "Work"]), (code, active, wall, names)
assert (D / "Work.json").read_text() == cfg("/b.png")
assert C.read_text() == cfg("/a.png")

assert run("switch", "Nope")[0] != 0
assert C.read_text() == cfg("/a.png"), "a switch to a missing profile touched the live config"

assert run("delete", "Default")[0] != 0 and (D / "Default.json").exists(), "deleted the active profile"
assert run("rename", "Default", "Work")[0] != 0, "renamed onto an existing profile"
assert run("rename", "Default", "Home")[:2] == (0, "Home")
assert run("delete", "Work")[3] == ["Home"]
print("profiles: ok")
