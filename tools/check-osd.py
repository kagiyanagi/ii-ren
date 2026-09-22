#!/usr/bin/env python3
"""Assert the OSD's expanded card fits its own buttons, and that it still leaves.

Two surfaces answer the volume key. `OnScreenDisplay.qml` is the edge dialog
`osd.style` "default" loads; `minimalist/MinimalistOsd.qml` is the top-centre pill
that "minimalist" and "material" load, and it is what the shipped config runs. Each
one shipped a defect that no screenshot of this machine would have shown.

**The card and the rows disagreed about how wide the card is.** The card grows to
`osdContractedWidth + extrasExpandedWidth` -- a number derived from how many *sliders*
the indicator has -- while each toggle row asked for `200 + 4 + osdButtonHeight` of
extras on its own authority. For volume with no app streams that is 252 wanted against
180 available, so the labels the expansion exists to reveal elided to `D…` and `Mut…`.
The labels are gone (AOSP's volume dialog has none) and the rows now take the same
`osdExtrasMaxWidth` the slider row takes, but the arithmetic still has to be swept:
whether it fits depends on the number of Pipewire playback nodes and on whether the
machine has a keyboard backlight, and a desktop with two streams and no backlight
exercises one point of that space. This evaluates the width expressions lifted out of
`OnScreenDisplay.qml` across the reachable range.

**The connected button group's radii are position-dependent.** A group end, and any
member that is on, is a pill; a seam between two members that are off is
`rounding.small`. Which *physical* side is the group's end flips with `osd.position`,
because the row's `layoutDirection` flips with it -- so a screenshot of a
right-anchored OSD proves exactly half of it, and the repo's own config is
right-anchored. Swept on both sides here.

**The minimalist OSD had no motion at all**, because `Loader.active` was bound
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
MINIMAL = (OSD_DIR / "minimalist/MinimalistOsd.qml").read_text()
SLIDERS = (OSD_DIR / "components/OsdSlidersRow.qml").read_text()
CONFIG = (ROOT / "modules/common/Config.qml").read_text()
APPEARANCE = (ROOT / "modules/common/Appearance.qml").read_text()

failures = []


def check(ok, msg):
    if not ok:
        failures.append(msg)


def one(src, pattern, what):
    m = re.search(pattern, src, re.M)
    assert m, f"{what} no longer matches {pattern!r} -- this check is stale"
    return m.group(1).strip()


def token(name):
    """A `readonly property real <name>: <number>` out of OnScreenDisplay.qml."""
    return float(one(OSD, rf"readonly property real {name}: (\d+(?:\.\d+)?)$", name))


def code(src):
    """The source with `//` comments dropped -- these files explain in prose what
    they must not contain, and a naive substring search finds the explanation."""
    return re.sub(r"//.*$", "", src, flags=re.M)


# ---------------------------------------------------------------- the dimens
# AOSP volume dialog, frameworks/base SystemUI res/values/dimens.xml. The file
# carries the citation; this reads the numbers back out so a retune fails here.
MARGIN = token("osdMargin")
ITEM_SPACING = token("osdItemSpacing")
ROW_SPACING = token("osdRowSpacing")
GROUP_SPACING = token("osdGroupSpacing")
BUTTON = token("osdButtonHeight")
SQUARED = token("osdSquaredButtonSize")

check(MARGIN == 6, f"osdMargin is {MARGIN}, AOSP background_margin is 6")
check(BUTTON == 48, f"osdButtonHeight is {BUTTON}, AOSP button_size is 48")
check(
    2 * MARGIN + BUTTON == 60,
    "the collapsed card is no longer AOSP's volume_dialog_width 60 "
    f"(2 * {MARGIN} + {BUTTON})",
)
check(
    SQUARED <= BUTTON,
    f"the squared button ({SQUARED}) is wider than the column it sits in ({BUTTON})",
)


def extras_expanded_width(indicator, playback_count, has_keyboard_backlight):
    """`extrasExpandedWidth` from OnScreenDisplay.qml -- the width the card grows by."""
    if indicator == "volume":
        sliders = (2 + playback_count) * BUTTON
        if playback_count > 0:
            return sliders + 2 * GROUP_SPACING + playback_count * ROW_SPACING
        return sliders + GROUP_SPACING + ROW_SPACING
    if indicator in ("brightness", "gamma"):
        n = 2 + (1 if has_keyboard_backlight else 0)
        return n * BUTTON + 2 * GROUP_SPACING + (n - 1) * ROW_SPACING
    return 0.0


# How many icon buttons each row puts on screen when the card is open. The primary
# one is pinned at the screen edge and is not part of the extras run.
ROWS = {
    # indicator: (top extras, bottom extras)
    "volume": (2, 2),          # system sounds + output devices / easyeffects + mic
    "brightness": (2, 2),      # nightlight + auto / kbd backlight + gamma reset
    "gamma": (2, 2),
}


def sweep():
    for indicator, (top, bottom) in ROWS.items():
        for playback in range(0, 9):
            for kbd in (False, True):
                if indicator == "volume" and kbd:
                    continue  # the volume card does not vary with the backlight
                if indicator != "volume" and playback:
                    continue  # nor the display card with playback streams
                extras = extras_expanded_width(indicator, playback, kbd)
                card = 2 * MARGIN + BUTTON + extras
                interior = card - 2 * MARGIN
                for name, count in (("top", top), ("bottom", bottom)):
                    # primary + gap + the extras run, all inside the card's padding
                    run = count * BUTTON + (count - 1) * ITEM_SPACING
                    needed = BUTTON + ROW_SPACING + run
                    yield indicator, playback, kbd, name, needed, interior


for indicator, playback, kbd, name, needed, interior in sweep():
    check(
        needed <= interior,
        f"{indicator} {name} row needs {needed:g}px but the card's interior is "
        f"{interior:g}px (playback={playback}, keyboardBacklight={kbd}) -- this is "
        "the overflow that elided every label to two characters",
    )
    # A row that fits but only just is the same bug one Pipewire node away.
    check(
        interior - needed >= 0,
        f"{indicator} {name} row has no slack at playback={playback}",
    )

# The extras containers must be sized by the card's own growth, never by a number of
# their own. This is the literal that caused the overflow.
check(
    "Layout.preferredWidth: osdRoot.osdExtrasMaxWidth * osdRoot.expandedProgress" in OSD,
    "the extras container no longer takes its width from osdExtrasMaxWidth -- "
    "the rows are guessing the card's width again",
)
check(
    not re.search(r"Layout\.preferredWidth: \(200 \+", code(OSD)),
    "a toggle row is asking for a hand-written 200px again",
)

# ------------------------------------------------- the connected button group
RSMALL = float(one(APPEARANCE, r"property int small: (\d+) \* scale", "rounding.small"))
check(RSMALL > 0, "rounding.small resolved to 0")


def group_radii(index, count, toggled, position):
    """`leftRadiusCalc` / `rightRadiusCalc` from OsdMorphToggle, as (left, right).

    `toggled` is the on/off state of every member of the run, in child order.
    """
    is_first = index == 0
    is_last = index == count - 1
    prev_on = toggled[index - 1] if index > 0 else False
    next_on = toggled[index + 1] if index < count - 1 else False
    on = toggled[index]
    leading = "pill" if (is_first or on or prev_on) else "small"
    trailing = "pill" if (is_last or on or next_on) else "small"
    if position == "left":
        return leading, trailing
    return trailing, leading


for position in ("left", "right"):
    # A run of three, all off: the two outer ends are pills, both seams are small.
    off = [False, False, False]
    left0, right0 = group_radii(0, 3, off, position)
    left1, right1 = group_radii(1, 3, off, position)
    left2, right2 = group_radii(2, 3, off, position)
    outer_first = left0 if position == "left" else right0
    inner_first = right0 if position == "left" else left0
    outer_last = right2 if position == "left" else left2
    check(outer_first == "pill", f"{position}: the run's first end is not a pill")
    check(inner_first == "small", f"{position}: the first seam is not rounding.small")
    check(outer_last == "pill", f"{position}: the run's last end is not a pill")
    check(
        (left1, right1) == ("small", "small"),
        f"{position}: a middle member with both neighbours off is not squared on both seams",
    )

    # A member that is on is a pill on both sides, and so are the seams facing it --
    # that is the M3 Expressive selection morph, not a rounding accident.
    on_middle = [False, True, False]
    check(
        group_radii(1, 3, on_middle, position) == ("pill", "pill"),
        f"{position}: a toggled member is not a pill on both sides",
    )
    check(
        "small" not in group_radii(0, 3, on_middle, position),
        f"{position}: the seam facing a toggled neighbour did not open up",
    )

    # A group of one -- the primary button, which is the collapsed dialog's whole
    # face -- is a pill regardless of where it sits in its parent's child list.
    check(
        group_radii(0, 1, [False], position) == ("pill", "pill"),
        f"{position}: a standalone toggle is not a pill",
    )

check(
    "property bool standalone: false" in OSD,
    "OsdMorphToggle lost `standalone`; the primary button is a group of one and "
    "without it the seam facing the extras squares off the collapsed dialog",
)
check(
    re.search(r"readonly property int indexInGroup: group\?\.children\.indexOf", OSD),
    "OsdMorphToggle no longer derives its neighbours from the row's child list -- "
    "hand-assigned _leftNeighbor/_rightNeighbor is what nine copy-pasted toggles "
    "were built on",
)

# `icon` and `checked` are final members of QQuickAbstractButton. Shadowing a final
# member is DESIGN.md anti-pattern 9, and qmllint is the only thing that says so.
for shadowed in ("icon", "checked"):
    check(
        not re.search(rf"^\s*property \w+ {shadowed}\b", OSD, re.M),
        f"OsdMorphToggle declares `{shadowed}`, which shadows a final member of "
        "QQuickAbstractButton",
    )

# ------------------------------------------------------------- the minimalist pill
check(
    re.search(r"active: GlobalStates\.osdVolumeOpen \|\| root\.isClosing", MINIMAL),
    "MinimalistOsd's Loader is gated on the open request alone again -- the surface "
    "is then destroyed on the frame the flag clears and the exit plays to nobody",
)
check(
    not re.search(r"visible: .*osdLoader\.active", MINIMAL),
    "MinimalistOsd's window is bound to the loader again, which unmaps it before the "
    "exit can run",
)
check(
    "onOpenedProgressChanged" in MINIMAL and "root.isClosing = false" in MINIMAL,
    "nothing releases MinimalistOsd's isClosing latch; the surface never goes away",
)
# The masked item must move by an anchor margin. A transform on it bakes into the
# input region and never refreshes (check-mask-regions.py has the full argument).
masked = one(MINIMAL, r"mask: Region \{\s*item: (\w+)", "MinimalistOsd's mask")
wrapper = one(
    MINIMAL,
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
    "elementMoveEnter" in MINIMAL and "elementMoveExit" in MINIMAL,
    "MinimalistOsd no longer names both an enter and an exit spec",
)

# ------------------------------------------------------ what must stay deleted
for gone in ("OsdSectionLabel", "OsdDeviceOutputButton", "OsdToggleRow"):
    check(
        not (OSD_DIR / f"components/{gone}.qml").exists(),
        f"{gone}.qml is back; every instantiation of it was `visible: false` or a "
        "contradiction",
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

# The slider row's fade masked a zero-width item for its whole life: the layer was
# gated on the indicator being neither volume nor a display one, and for exactly
# those indicators extrasExpandedWidth is 0.
for indicator in ("playerVolume", "keyboardBrightness"):
    check(
        extras_expanded_width(indicator, 4, True) == 0,
        f"{indicator} now has extras, so the fade the layer was for may be real again",
    )
for banned in ("layer.enabled", "OpacityMask", "Canvas"):
    check(
        banned not in code(SLIDERS),
        f"OsdSlidersRow carries `{banned}` again -- three offscreen passes for a "
        "gradient that only ever ran over a zero-width item",
    )

# One shadow on the dialog, and the cached rectangular one, since the container is a
# plain rounded rectangle (DESIGN.md 6.2 / 8).
check(
    code(OSD).count("StyledDropShadow") == 0,
    "the OSD is back on StyledDropShadow; osdContainer is a rounded Rectangle and "
    "StyledRectangularShadow is cached",
)
check(
    code(OSD).count("StyledRectangularShadow") == 1,
    f"the OSD draws {code(OSD).count('StyledRectangularShadow')} shadows; the budget is one",
)

if failures:
    print(f"check-osd.py: {len(failures)} failure(s)\n")
    for f in failures:
        print(f"  FAIL  {f}")
    sys.exit(1)
print("ok: OSD card fits its rows, the button group reads both positions, the "
      "minimalist pill still leaves")
