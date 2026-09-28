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

Run: python3 tools/check-osd.py
"""
import pathlib
import re
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

if failures:
    print(f"check-osd.py: {len(failures)} failure(s)\n")
    for f in failures:
        print(f"  FAIL  {f}")
    sys.exit(1)
print("ok: the OSD pill still leaves, and only the Material style exists")
