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

if failures:
    print(f"check-osd.py: {len(failures)} failure(s)\n")
    for f in failures:
        print(f"  FAIL  {f}")
    sys.exit(1)
print("ok: the OSD pill still leaves, only the Material style exists, and the keyboard pill reads a real 0-1 level")
