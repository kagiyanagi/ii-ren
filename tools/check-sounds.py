#!/usr/bin/env python3
"""Every system sound category is wired end to end: caller, config key, settings row.

SoundService.playEvent(category) plays only while Config.options.sounds[category] is
true, and reads that key by name. Nothing fails when the key does not exist: the
lookup is undefined, the sound never plays, and the log says nothing. The lock and
login sounds shipped like that -- SoundService fired them, Config.qml never declared
`lock` or `session`, so neither ever played. This pins each category named by a
caller to SoundService.events, to a bool in Config.qml's sounds block, and to a row on
the Sounds page, and each custom-file key to a category with a file button. It also
holds the bundled Android theme to freedesktop names the shell actually asks for.
"""
import pathlib, re

SHELL = pathlib.Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
service = (SHELL / "services/SoundService.qml").read_text()
config = (SHELL / "modules/common/Config.qml").read_text()
page = (SHELL / "modules/settings/SoundsConfig.qml").read_text()

m = re.search(r"readonly property var events: \(\{(.*?)\}\)", service, re.S)
assert m, "SoundService no longer declares its events table"
events = dict(re.findall(r"^\s*(\w+): \[([^\]]*)\]", m.group(1), re.M))
assert len(events) >= 8, f"could not read SoundService.events ({list(events)})"

block = config[config.index("property JsonObject sounds: JsonObject {"):]
block = block[:block.index("property string theme:")]
custom = block[block.index("property JsonObject custom"):]
custom = custom[:custom.index("}")]
bools = set(re.findall(r"property bool (\w+):", block))
custom_keys = set(re.findall(r"property string (\w+):", custom))

callers = {}
for f in SHELL.rglob("*.qml"):
    if "user_widgets" in f.parts:
        continue
    for cat in re.findall(r"""SoundService\.(?:playEvent|startLoop)\(\s*["'](\w+)["']""", f.read_text()):
        callers.setdefault(cat, set()).add(f.relative_to(SHELL).as_posix())
assert callers, "found no SoundService.playEvent callers at all"

for cat, files in sorted(callers.items()):
    where = ", ".join(sorted(files))
    assert cat in events, f"{where} plays '{cat}', which SoundService.events does not list"
for cat in events:
    assert cat in bools, f"'{cat}' has no `property bool {cat}` in Config.qml's sounds block, so it never plays"
    assert re.search(rf"checked: page\.opts\.{cat}\b", page), f"'{cat}' has no switch on the Sounds page"
for key in custom_keys:
    assert key in events, f"Config sounds.custom.{key} is not a category"
    assert f'FileButton {{ category: "{key}" }}' in page, f"sounds.custom.{key} has no file button on the Sounds page"

# The bundled theme: an index the scan accepts, inheriting what it lacks, and only
# files named by an event some caller or the events table asks for.
theme = SHELL / "assets/sounds/aosp"
index = (theme / "index.theme").read_text()
assert "[Sound Theme]" in index and re.search(r"^Inherits=freedesktop$", index, re.M), "aosp/index.theme must inherit freedesktop"
asked = set(re.findall(r'"([a-z]+(?:-[a-z]+)+)"', "\n".join(f.read_text() for f in SHELL.rglob("*.qml") if "user_widgets" not in f.parts)))
files = sorted(p.stem for p in (theme / "stereo").iterdir())
assert files, "the aosp theme has no sounds"
for name in files:
    assert name in asked, f"aosp/stereo/{name} is a sound no part of the shell asks for"
assert (theme / "LICENSE").exists(), "the AOSP sounds are Apache-2.0: keep the LICENSE beside them"

print(f"ok: {len(events)} sound categories wired to config and the Sounds page, {len(files)} bundled Android sounds")
