#!/usr/bin/env python3
"""Assert the OSD still leaves, and that the styles it used to offer stay deleted.

The volume key answers with one surface: `OnScreenDisplay.qml`, the top-centre pill
around `OsdMaterialValueIndicator`. It used to be one of three -- an edge "Android"
dialog and a "Minimal" indicator sat behind `osd.style` -- and those were removed
outright, config keys and settings rows with them.

**The OSD had no motion at all**, because `Loader.active` was bound
straight to `GlobalStates.osdVolumeOpen`: the surface was built and destroyed on the
frame the flag flipped, so there was nothing alive to play an exit on. That is the
same shape that deleted the drop shelf's exit, the media popup's and the notification
stack's, and it has no symptom -- the card is supposed to disappear. Held structurally,
along with the `mask` on an item that must therefore move by an anchor margin rather
than a transform (a transform freezes the input region; see check-mask-regions.py).

**And the controls that never worked stay deleted.** `Config.options.sounds.monoAudio`
is not a member of `Config.qml`'s `sounds` object and `MonoAudioService` is not a file
in this repo, so the stereo/mono toggle read `undefined` and threw a ReferenceError on
click for as long as it existed (DESIGN.md anti-pattern 16).

**The keyboard-backlight OSD read a property the service never had.**
`KeyboardBrightnessIndicator` bound `KeyboardBacklight.percentage / 100`, but the service
exposes `currentValue` and `maxValue` (kernel levels, 0..2 on a Dell), so the pill showed
NaN every time the backlight changed. QML reads an unknown property on a singleton as
`undefined` without a warning, so every `KeyboardBacklight.<member>` the shell reads is
checked against the service, and the indicator's `value:` is run under node for a normal
LED and for one whose `max_brightness` has not loaded yet (`maxValue` 0 -- 0/0 is NaN).

**The volume pill turned red at 100% with earbang protection off.** `VolumeIndicator`
set `maxLimit` from `protection.maxAllowed` (99 by default) whether or not protection
was on, so the error colour -- "over the limit" -- showed at a volume nothing limits.
The limit is `maxAllowed` only while protection is on, and inclusive, since
`Audio.setVolume` clamps *to* it; with protection off it is 100%, past which the volume
keys overamplify (`-l 1.5`). PipeWire hands the volume back as a cube root of float32
channel volumes, so 100% reads 1.0000001 and 99% 0.98999995: the pill goes red when the
number it shows is past the limit, not on that noise. The binding is run under node,
through the base's own `value > maxLimit`, for each side of each limit.

**"Hide when fullscreen" never hid anything.** The gate read
`Notifications.focusedWindowFullscreen`, which `Notifications` has never declared, so
it was undefined and the option (on by default) did nothing. Every `<Singleton>.<name>`
either OSD (ii and Waffle) reads is now checked against the members on that singleton's
root object. The gate is per monitor, like the dock's and the Waffle OSD's: a fullscreen
window on the screen the OSD opens on hides it, one on the other monitor does not. Its
function is run under node against workspaces on two monitors.

**A player's volume showed the system volume.** The `playerVolume` entry loaded
`VolumeIndicator`, which binds `Audio.sink`, so changing Spotify's own volume popped a
pill with the sink's number in it -- and the sink's protection red. The player pill
reads the player's MPRIS volume and never warns: the limit is the sink's, and a player
at 100% (or mpv at 130%) is not over anything. It shows the player whose volume changed,
held by the OSD, not whatever `activePlayer` is by the time it draws. Its bindings run
under node against a sink, an active player and the changed player that all differ.

Run: python3 tools/check-osd.py
"""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii"
OSD_DIR = ROOT / "modules/ii/onScreenDisplay"
OSD = (OSD_DIR / "OnScreenDisplay.qml").read_text()
CONFIG = (ROOT / "modules/common/Config.qml").read_text()
SETTINGS = (ROOT / "modules/settings/InterfaceConfig.qml").read_text()

failures = []


def check(ok, msg):
    if not ok:
        failures.append(msg)


def one(src, pattern, what):
    m = re.search(pattern, src, re.M)
    assert m, f"{what} no longer matches {pattern!r} -- this check is stale"
    return m.group(1).strip()


def code(src):
    """The source with `//` comments dropped -- these files explain in prose what
    they must not contain, and a naive substring search finds the explanation."""
    return re.sub(r"//.*$", "", src, flags=re.M)


# ------------------------------------------------------------------- the pill
check(
    re.search(r"active: GlobalStates\.osdVolumeOpen \|\| root\.isClosing", OSD),
    "OnScreenDisplay's Loader is gated on the open request alone again -- the surface "
    "is then destroyed on the frame the flag clears and the exit plays to nobody",
)
check(
    not re.search(r"visible: .*osdLoader\.active", OSD),
    "OnScreenDisplay's window is bound to the loader again, which unmaps it before the "
    "exit can run",
)
check(
    "onOpenedProgressChanged" in OSD and "root.isClosing = false" in OSD,
    "nothing releases OnScreenDisplay's isClosing latch; the surface never goes away",
)
# The masked item must move by an anchor margin. A transform on it bakes into the
# input region and never refreshes (check-mask-regions.py has the full argument).
masked = one(OSD, r"mask: Region \{\s*item: (\w+)", "OnScreenDisplay's mask")
wrapper = one(
    OSD,
    rf"Item \{{\s*id: {masked}\n((?:.+\n)+?)\s*// The OSD is an acknowledgement",
    f"the {masked} block",
)
check(
    "anchors.topMargin" in wrapper or "anchors.bottomMargin" in wrapper,
    f"{masked} no longer slides on an anchor margin",
)
for banned in ("scale:", "transform:", "transformOrigin:"):
    check(
        banned not in code(wrapper),
        f"{masked} carries `{banned}` and is also the mask's item -- the input region "
        "freezes at whatever the transform was when the geometry last changed",
    )
# Enter and exit are not the same spec (DESIGN.md 2.5), and the one that is picked has
# to be assigned from inside the handler, not read by the Behavior (2.9).
check(
    "elementMoveEnter" in OSD and "elementMoveExit" in OSD,
    "OnScreenDisplay no longer names both an enter and an exit spec",
)

# ------------------------------------------------------ what must stay deleted
for gone in ("OsdValueIndicator.qml", "components", "popups", "minimalist"):
    check(
        not (OSD_DIR / gone).exists(),
        f"onScreenDisplay/{gone} is back; the Android and Minimal OSD styles were removed",
    )
check(
    not re.search(r"property \w+ (style|position|height):", CONFIG.split("property JsonObject osd:")[1].split("property JsonObject languageSwitcher:")[0]),
    "Config.qml's osd object grew style/position/height again -- nothing reads them",
)
check(
    "osd.style" not in code(SETTINGS) and "OsdPositionPicker" not in SETTINGS,
    "the settings page offers an OSD style or position again",
)

check(
    "monoAudio" not in code(CONFIG),
    "Config.qml grew a `monoAudio` key -- the OSD toggle bound to it was deleted "
    "because neither it nor MonoAudioService existed; wire both or neither",
)
check(
    not list(ROOT.rglob("MonoAudioService.qml")),
    "MonoAudioService.qml exists now; the OSD's stereo/mono toggle can come back",
)

# ------------------------------------------------- the keyboard backlight pill
KBD = (ROOT / "services/KeyboardBacklight.qml").read_text()
KBD_OSD = (OSD_DIR / "indicators/KeyboardBrightnessIndicator.qml").read_text()
props = set(re.findall(r"^\s*(?:readonly )?property \w+ (\w+)", KBD, re.M))
members = props | set(re.findall(r"^\s*function (\w+)\(", KBD, re.M))
for path in ROOT.rglob("*"):
    if path.suffix not in (".qml", ".js"):
        continue
    src = code(path.read_text())
    rel = path.relative_to(ROOT)
    for name in sorted(set(re.findall(r"\bKeyboardBacklight\.(\w+)", src))):
        check(
            name in members,
            f"{rel} reads KeyboardBacklight.{name}, which the service does not have -- "
            "QML hands back undefined, and arithmetic on it is NaN",
        )
    # A Connections handler on a property that does not exist never fires.
    for block in re.findall(r"Connections \{\s*target: KeyboardBacklight\n(.*?)\n\s*\}\n", src, re.S):
        for prop in re.findall(r"function on(\w+)Changed\(", block):
            check(
                prop[0].lower() + prop[1:] in props,
                f"{rel} listens for KeyboardBacklight.{prop[0].lower() + prop[1:]} "
                "changing, which the service does not have",
            )

value_expr = one(KBD_OSD, r"^\s*value: (.+)$", "KeyboardBrightnessIndicator's value")
icon_expr = one(KBD_OSD, r"^\s*icon: (.+)$", "KeyboardBrightnessIndicator's icon")
leds = [(0, 0), (1, 0), (0, 1), (1, 1), (0, 2), (1, 2), (2, 2), (0, 3), (3, 3)]
shown = json.loads(subprocess.run(["node", "-e", f"""
console.log(JSON.stringify({json.dumps(leds)}.map(([cur, max]) => {{
    const KeyboardBacklight = {{ currentValue: cur, maxValue: max, available: max > 0 }};
    return {{ value: {value_expr}, icon: {icon_expr} }};
}})));
"""], capture_output=True, text=True, check=True).stdout)
symbols = set((ROOT / "assets/material-symbols.txt").read_text().split())
for (cur, max_), out in zip(leds, shown):
    v = out.get("value")  # NaN serialises as null, undefined not at all
    check(
        isinstance(v, (int, float)) and 0 <= v <= 1,
        f"the keyboard OSD shows {v!r} for level {cur} of {max_}; the indicator takes a "
        "finite 0-1 fraction",
    )
    if max_ > 0:
        check(
            isinstance(v, (int, float)) and abs(v - cur / max_) < 1e-9,
            f"the keyboard OSD shows {v!r} for level {cur} of {max_}, not {cur / max_}",
        )
    check(
        out.get("icon") in symbols,
        f"the keyboard OSD's icon {out.get('icon')!r} is not a Material Symbol every installed "
        "font has, so it renders as the word",
    )

# ------------------------------------------------------ the volume pill's warning
BASE = code((OSD_DIR / "OsdMaterialValueIndicator.qml").read_text())
VOL_OSD = (OSD_DIR / "indicators/VolumeIndicator.qml").read_text()
# The cases below model the base's comparison; a pill that warns some other way
# needs them rewritten, not silently passing.
check(
    "property real maxLimit:" in BASE
    and len(re.findall(r"\bmaxLimit\b", BASE)) == 1 + BASE.count("root.value > root.maxLimit"),
    "OsdMaterialValueIndicator reads maxLimit other than as `root.value > root.maxLimit` "
    "-- the volume warning cases in this check no longer model it",
)
limit_expr = one(VOL_OSD, r"^\s*maxLimit: (.+)$", "VolumeIndicator's maxLimit")
# (protection on, maxAllowed %, volume as PipeWire reports it, warns)
cases = [
    (False, 99, 1.0, False),         # the bug: red at 100% with nothing limiting
    (False, 99, 1.0000001, False),   # 100% as the cube root of a float32
    (False, 99, 0.99, False),
    (False, 99, 1.02, True),         # overamplified
    (False, 99, 1.5, True),
    (True, 99, 0.98, False),         # below the limit
    (True, 99, 0.99, False),         # at it: Audio clamps to it, so it is allowed
    (True, 99, 0.98999995, False),   # at it, float noise either side
    (True, 99, 0.99000007, False),
    (True, 99, 1.0, True),           # above it
    (True, 120, 1.0, False),
    (True, 120, 1.2000001, False),
    (True, 120, 1.22, True),
]
warns = json.loads(subprocess.run(["node", "-e", f"""
console.log(JSON.stringify({json.dumps(cases)}.map(([enable, maxAllowed, volume]) => {{
    const Config = {{ options: {{ audio: {{ protection: {{ enable, maxAllowed, maxAllowedIncrease: 10 }} }} }} }};
    return volume > ({limit_expr});
}})));
"""], capture_output=True, text=True, check=True).stdout)
for (enable, max_allowed, volume, want), got in zip(cases, warns):
    protection = f"on at {max_allowed}%" if enable else "off"
    check(
        got == want,
        f"the volume pill {'warns' if got else 'does not warn'} at {volume!r} with "
        f"protection {protection}; it should {'' if want else 'not '}turn red",
    )

# ------------------------------------------------------- the player volume pill
# The OSD holds the player that sent volumeChanged and hands that to the pill.
handler = re.search(
    r"Connections \{\s*(?:id: (\w+)\s*)?target: MprisController\.activePlayer.*?\n"
    r"(.*?function onVolumeChanged\(\).*?)\n    \}\n",
    OSD, re.S,
)
assert handler, "OnScreenDisplay's player volume Connections no longer matches -- this check is stale"
held = re.search(
    rf"root\.(\w+) = (?:{handler.group(1) or 'Connections'}\.target|MprisController\.activePlayer);",
    handler.group(2),
)
check(
    held,
    "OnScreenDisplay's player volumeChanged handler no longer records which player changed; "
    "the pill then follows activePlayer, which can move while it is up",
)
if held:
    check(
        re.search(rf"\.player = Qt\.binding\(\(\) => root\.{held.group(1)}\)", OSD),
        f"OnScreenDisplay records the changed player in {held.group(1)} but no longer hands "
        "it to the playerVolume pill",
    )

indicator_src = {
    m.group(1): m.group(2)
    for m in re.finditer(r'id: "(\w+)",\s*sourceUrl: "([^"]+)"', OSD)
}
player_url = indicator_src.get("playerVolume")
assert player_url, "OnScreenDisplay's playerVolume entry no longer matches -- this check is stale"
own_pill = player_url != indicator_src.get("volume")
check(
    own_pill,
    "the playerVolume pill loads the system volume pill again, so a player's volume "
    "change shows the sink's volume",
)
if own_pill:
    PLAYER_OSD = code((OSD_DIR / player_url).read_text())
    for banned, why in (
        ("Audio.", "the sink is the system volume, not the player's"),
        ("protection", "the protection limit is the sink's; a player at 100% is not past it"),
        ("MprisController.", "the active player may not be the one whose volume changed"),
    ):
        check(banned not in PLAYER_OSD, f"{player_url} reads `{banned}` -- {why}")

    base_limit = one(BASE, r"property real maxLimit: (.+)$", "OsdMaterialValueIndicator's maxLimit")
    player_value = one(PLAYER_OSD, r"^\s*value: (.+)$", f"{player_url}'s value")
    player_icon = one(PLAYER_OSD, r"^\s*icon: (.+)$", f"{player_url}'s icon")
    player_limit = re.search(r"^\s*maxLimit: (.+)$", PLAYER_OSD, re.M)
    player_limit = player_limit.group(1).strip() if player_limit else base_limit
    # MPRIS volume is linear 0-1, and some players allow more (mpv to 1.3); None = gone.
    player_volumes = [0, 0.3, 0.5, 0.99, 1.0, 1.0000001, 1.3, None]
    pills = json.loads(subprocess.run(["node", "-e", f"""
console.log(JSON.stringify({json.dumps(player_volumes)}.map(v => {{
    const Audio = {{ sink: {{ audio: {{ volume: 0.25, muted: true }} }} }};
    const MprisController = {{ activePlayer: {{ volume: 0.6 }}, canChangeVolume: true }};
    const Config = {{ options: {{ audio: {{ protection: {{ enable: true, maxAllowed: 99 }} }} }} }};
    const root = {{ player: v === null ? null : {{ volume: v }} }};
    root.value = {player_value};
    const icon = {player_icon};
    return {{ value: root.value, icon, warns: root.value > ({player_limit}) }};
}})));
"""], capture_output=True, text=True, check=True).stdout)
    for volume, out in zip(player_volumes, pills):
        want = volume if volume is not None else 0
        check(
            isinstance(out.get("value"), (int, float)) and abs(out["value"] - want) < 1e-9,
            f"the player pill shows {out.get('value')!r} for a player at {volume!r}; it should "
            f"show the player's own {want!r}, not the sink's 0.25 or the active player's 0.6",
        )
        check(
            not out.get("warns"),
            f"the player pill turns red at {volume!r} -- the protection limit is the sink's",
        )
        check(
            out.get("icon") in symbols,
            f"the player pill's icon {out.get('icon')!r} is not a Material Symbol every "
            "installed font has, so it renders as the word",
        )
    check(
        pills[0].get("icon") != pills[1].get("icon"),
        "the player pill shows the same icon at 0 as above it; MPRIS has no mute, so 0 is "
        "the player's muted state and should look it",
    )

# ------------------------------------------- every singleton the OSD reads, for real
def blank(src):
    """`src` with comments and string literals blanked, newlines kept: what is left
    is only code, so its braces balance and a name in a string is not a read."""
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith("//", i):
            i = n if src.find("\n", i) < 0 else src.find("\n", i)
        elif src.startswith("/*", i):
            j = n if src.find("*/", i + 2) < 0 else src.find("*/", i + 2) + 2
            out.append(re.sub(r"[^\n]", " ", src[i:j]))
            i = j
        elif src[i] in "'\"`":
            j = i + 1
            while j < n and src[j] != src[i]:
                j += 2 if src[j] == "\\" else 1
            out.append(src[i] + re.sub(r"[^\n]", " ", src[i + 1:j]) + src[i])
            i = j + 1
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


def root_members(path):
    """The properties, functions and signals declared on a QML file's root object --
    nested objects' members are not reachable as `Singleton.name`."""
    names, depth = set(), 0
    for line in blank(path.read_text()).splitlines():
        if depth == 1:
            m = re.match(r"\s*(?:(?:readonly|required|default)\s+)*(?:property\s+[\w.<>]+|function|signal)\s+(\w+)", line)
            if m:
                names.add(m.group(1))
        depth += line.count("{") - line.count("}")
        assert depth >= 0, f"{path.relative_to(ROOT)}: braces no longer balance -- this check is stale"
    assert depth == 0, f"{path.relative_to(ROOT)}: braces no longer balance -- this check is stale"
    return names


SINGLETONS = {p.stem: p for p in ROOT.rglob("*.qml") if re.search(r"^pragma Singleton", p.read_text(), re.M)}
declared = {}
for folder in (OSD_DIR, ROOT / "modules/waffle/onScreenDisplay"):
    for path in sorted(folder.rglob("*.qml")):
        rel = path.relative_to(ROOT)
        for single, name in sorted(set(re.findall(r"(?<![\w.])([A-Z]\w*)\??\.([a-z_]\w*)", blank(path.read_text())))):
            if single not in SINGLETONS:
                continue  # Quickshell's own (Hyprland, Quickshell) or an attached type
            if single not in declared:
                declared[single] = root_members(SINGLETONS[single])
            check(
                name in declared[single],
                f"{rel} reads {single}.{name}, which {SINGLETONS[single].relative_to(ROOT)} does "
                "not declare -- QML hands back undefined without a warning, so a gate on it "
                "never closes",
            )

# The OSD's "Hide when fullscreen" read `Notifications.focusedWindowFullscreen` from the
# day it was written; Notifications never had it, so the option did nothing. The gate is
# per monitor, like the dock's: only a fullscreen window on the screen the OSD opens on
# hides it, not one playing on the other monitor.
gate = re.search(r"hideWhenFullscreen && root\.(\w+)\(\)\)\n\s*return;", OSD)
check(
    gate,
    "OnScreenDisplay's hideWhenFullscreen gate no longer asks a root function whether the "
    "OSD's screen has a fullscreen window, so the cases below cannot run against it",
)
# (OSD screen, [(monitor, active, [toplevel fullscreen; None = no Wayland handle yet])], hides)
screens = [
    ("DP-1", [("DP-1", True, [False, True])], True),
    ("DP-1", [("DP-1", True, [False]), ("DP-1", False, [True])], False),   # a workspace out of sight
    ("DP-1", [("DP-1", True, [False]), ("HDMI-A-1", True, [True])], False),  # the other monitor
    ("HDMI-A-1", [("DP-1", True, [False]), ("HDMI-A-1", True, [True])], True),
    ("DP-1", [("DP-1", True, [None])], False),
    ("DP-1", [(None, True, [True])], False),
    ("DP-1", [], False),
    (None, [("DP-1", True, [True])], False),
]
if gate:
    body = one(
        OSD,
        rf"function {gate.group(1)}\(\) \{{\n((?:.+\n)+?)    \}}\n",
        f"OnScreenDisplay's {gate.group(1)}()",
    )
    hides = json.loads(subprocess.run(["node", "-e", f"""
console.log(JSON.stringify({json.dumps(screens)}.map(([screen, workspaces]) => {{
    const root = {{ focusedScreen: screen === null ? null : {{ name: screen }} }};
    const Hyprland = {{ workspaces: {{ values: workspaces.map(([monitor, active, toplevels]) => ({{
        active,
        monitor: monitor === null ? null : {{ name: monitor }},
        toplevels: {{ values: toplevels.map(f => ({{ wayland: f === null ? null : {{ fullscreen: f }} }})) }},
    }})) }} }};
    return Boolean((function () {{ {body} }})());
}})));
"""], capture_output=True, text=True, check=True).stdout)
    for (screen, workspaces, want), got in zip(screens, hides):
        check(
            got == want,
            f"with the OSD on {screen!r} and workspaces {workspaces!r} (monitor, active, "
            f"fullscreen toplevels), hideWhenFullscreen {'hides' if got else 'shows'} the OSD; "
            f"it should {'hide' if want else 'show'} it",
        )

if failures:
    print(f"check-osd.py: {len(failures)} failure(s)\n")
    for f in failures:
        print(f"  FAIL  {f}")
    sys.exit(1)
print("ok: the OSD pill still leaves, only the Material style exists, the keyboard pill reads a real 0-1 level, the volume pill warns only past its limit, the player pill shows the player's own volume, and every singleton the OSDs read is real -- hide-when-fullscreen included, per monitor")
