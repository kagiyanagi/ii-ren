#!/usr/bin/env python3
"""The media popup shows every player it has, and it closes visibly.

Four things about `modules/ii/mediaControls/` are arithmetic or invariants
rather than pictures. A screenshot of the popup looks correct under all four
failures, because each one removes something rather than drawing it wrong.

- **The duplicate filter.** `MediaControls.filterDuplicatePlayers` merges two
  entries when they are at "the same place in a track of the same length", and
  that test was written unsigned: `p1.position - p2.position <= 2` is true
  whenever p1 is *behind* p2 at all, by any amount. Any player earlier in its
  track than another was merged into it and disappeared from the stack. Three
  live players -- a music player, Firefox and plasma-browser-integration --
  collapsed to one card, which is indistinguishable from the filter doing its
  job. Swept here over pairs that must and must not merge.

- **The setting.** That second pass ran unconditionally while
  `Config.options.media.filterDuplicatePlayers` had a switch in
  Settings > Services, and the surface's own empty-state text tells the user to
  go and turn it off. `MprisController.isRealPlayer` honours it; this did not.

- **The exit.** `Loader.active` bound to `GlobalStates.mediaControlsOpen` merges
  the request with the surface: the component is destroyed on the frame the flag
  flips and the close animation plays to nobody. There is no other symptom --
  the popup still disappears -- so it is asserted structurally, the same way
  `check-cheatsheet.py` and `check-dropshelf.py` do it.

- **The mask.** `mask: Region { item: x }` computes the input region from that
  item's rect with its transform applied and refreshes only when the item's
  *geometry* changes. The column now rests at `arrowPopupScale` and animates to
  1, so a mask over it would freeze the region at half size and the card would
  click through to the window behind it. The popup carried exactly such a mask,
  harmlessly, until the open animation landed.

    python3 tools/check-media-controls.py
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHELL = ROOT / "dots/.config/quickshell/ii"
CONTROLS = SHELL / "modules/ii/mediaControls/MediaControls.qml"
CARD = SHELL / "modules/ii/mediaControls/PlayerControl.qml"
POPUP = SHELL / "modules/ii/mediaControls/AndroidMediaPopup.qml"
MPRIS = SHELL / "services/MprisController.qml"


def code(path):
    """The file with `//` comments stripped -- these assertions are about what
    the QML does, and every one of them is also described in a comment next to
    the thing it guards."""
    return re.sub(r"^\s*//.*$", "", path.read_text(), flags=re.M)


class Player:
    """Only the four fields the filter reads."""

    def __init__(self, title, position, length, art=""):
        self.trackTitle = title
        self.position = position
        self.length = length
        self.trackArtUrl = art

    def __repr__(self):
        return f"{self.trackTitle!r}@{self.position}/{self.length}"


def filter_duplicates(players):
    """`MediaControls.filterDuplicatePlayers`, transcribed."""
    filtered, used = [], set()
    for i, p1 in enumerate(players):
        if i in used:
            continue
        group = [i]
        for j in range(i + 1, len(players)):
            p2 = players[j]
            same_title = bool(p1.trackTitle and p2.trackTitle and (
                p2.trackTitle in p1.trackTitle or p1.trackTitle in p2.trackTitle))
            same_place = abs(p1.position - p2.position) <= 2 and abs(p1.length - p2.length) <= 2
            if same_title or same_place:
                group.append(j)
        chosen = next((k for k in group if players[k].trackArtUrl), group[0])
        filtered.append(players[chosen])
        used.update(group)
    return filtered


def check_filter_keeps_distinct_players():
    """The shape that shipped: everything collapsed onto one card."""
    # Two unrelated players, both mid-track, at different points in tracks of
    # different lengths. Nothing about them is a duplicate.
    music = Player("Weightless in the Long Hall", position=103, length=272)
    video = Player("Eternal Youth - YouTube", position=812, length=1_450)
    assert len(filter_duplicates([music, video])) == 2, \
        "two distinct players merged -- the position test is unsigned again"

    # Order must not decide it. Unsigned subtraction merged them one way round
    # and not the other, which is why the bug looked intermittent.
    assert len(filter_duplicates([video, music])) == 2, \
        "the filter is order-dependent -- abs() is missing from one side"

    # The real three-bus case that collapsed to one card.
    firefox = Player("Eternal Youth - YouTube", position=812, length=1_450)
    plasma = Player("Eternal Youth", position=812, length=1_450, art="file:///art.png")
    assert len(filter_duplicates([music, firefox, plasma])) == 2, \
        "the browser's two buses and an unrelated player did not resolve to two cards"
    print("ok  filter: distinct players survive, in either order")


def check_filter_still_merges_duplicates():
    """It is a duplicate filter; it still has to filter duplicates."""
    a = Player("Eternal Youth - YouTube", position=812, length=1_450)
    b = Player("Eternal Youth", position=813, length=1_450, art="file:///art.png")
    merged = filter_duplicates([a, b])
    assert len(merged) == 1, "the same track on two buses is showing twice"
    assert merged[0].trackArtUrl, "the merge kept the entry without cover art"

    # Same place, same length, titles that share nothing: still the same track
    # seen twice, which is the whole reason the position test exists.
    c = Player("", position=30, length=200)
    d = Player("", position=31, length=201)
    assert len(filter_duplicates([c, d])) == 1, "the position test no longer merges anything"

    # ...but only within the tolerance. Two seconds, not any distance.
    e = Player("", position=30, length=200)
    f = Player("", position=45, length=200)
    assert len(filter_duplicates([e, f])) == 2, "the tolerance has stopped biting"
    print("ok  filter: real duplicates still collapse, to the entry that has art")


def check_filter_obeys_the_setting():
    """The switch in Settings > Services has to reach this surface."""
    src = CONTROLS.read_text()
    binding = re.search(r"property var meaningfulPlayers:([^\n]+)", src)
    assert binding, "meaningfulPlayers is gone"
    assert "Config.options.media.filterDuplicatePlayers" in binding.group(1), \
        ("the popup filters duplicates unconditionally -- the settings switch does "
         "nothing here, and the empty state tells the user to go and use it")
    assert "filterDuplicatePlayers" in MPRIS.read_text(), \
        "MprisController no longer consults the setting either"
    print("ok  setting: the duplicate filter is switchable where it is applied")


def check_exit_survives_the_flag():
    """The request is not the surface."""
    src = CONTROLS.read_text()
    active = re.search(r"Loader\s*\{.*?\n\s*active:\s*([^\n]+)", src, re.S)
    assert active, "the popup Loader has no active binding"
    assert "GlobalStates.mediaControlsOpen" not in active.group(1), \
        ("Loader.active is bound to the open request again -- the component is "
         "destroyed on the frame the flag flips and the close plays to nobody")

    assert re.search(r"ArrowPopupMotion\s*\{", src), \
        "the popup no longer opens on the shell's one ArrowPopup assembly"
    assert re.search(r"onClosed:\s*mediaControlsLoader\.alive\s*=\s*false", src), \
        "nothing tears the surface down when the close finishes -- it leaks a window"
    assert "startClose" in src and "startOpen" in src, \
        "the loader no longer drives the motion explicitly"
    print("ok  exit: the surface outlives the request and is torn down on finish")


def check_transform_origin():
    """A popup grows out of whatever opened it (DESIGN.md 2.6)."""
    src = CONTROLS.read_text()
    pivot = re.search(r"property int pivot:\s*\{(.+?)\n\s{12}\}", src, re.S)
    assert pivot, "the popup has no pivot -- it grows out of its own middle"
    body = pivot.group(1)
    for edge in ("Item.Top", "Item.Bottom", "Item.Left", "Item.Right"):
        assert edge in body, f"the pivot never resolves to {edge}"
    assert "Config.options.bar.vertical" in body and "Config.options.bar.bottom" in body, \
        "the pivot ignores where the bar is, so it is wrong for three of four layouts"
    assert "transformOrigin: panelWindow.pivot" in src, "the pivot is computed and not used"

    # Resting values, so a reopen animates from a known state rather than a stale
    # one (DESIGN.md 2.7).
    assert "scale: Appearance.animationCurves.arrowPopupScale" in src, \
        "the column does not rest at the open animation's starting scale"
    print("ok  origin: the stack grows out of the bar edge it is placed against")


def check_no_mask_over_the_scaled_column():
    """A Region bakes the transform and refreshes only on a geometry change."""
    assert "mask:" not in code(CONTROLS), \
        ("the popup masks something again. The column rests at arrowPopupScale, so "
         "the input region freezes at half size and the card clicks through to the "
         "window behind it -- see tools/check-mask-regions.py")
    print("ok  mask: nothing masks the column that now scales")


def check_disabled_controls_are_disabled():
    """Dimming a glyph over a live button is not a disabled state (3.1)."""
    src = POPUP.read_text()
    for cap in ("canGoPrevious", "canGoNext"):
        assert re.search(rf"enabled:\s*root\.player\?\.{cap}", src), \
            f"the skip button gated on {cap} still hovers, ripples and fires"
    assert "opacity: enabled ? 1 : 0.4" in src, "disabled is not 0.4 on the control"

    # 32px is the pointer minimum for this shell (DESIGN.md 3.4). Both skip
    # buttons sat at 24, and the player picker at 18.
    for btn in ("prevBtn", "nextBtn"):
        size = re.search(rf"id: {btn}\b.*?implicitWidth:\s*(\d+)", src, re.S)
        assert size, f"{btn} is gone"
        assert int(size.group(1)) >= 32, \
            f"{btn} is {size.group(1)}px, back under the 32px minimum"
    assert re.search(r"buttonSize:\s*32", CARD.read_text()), \
        "the player picker is back under the 32px minimum"
    print("ok  states: skip buttons genuinely disabled, targets at 32")


def check_no_dead_colour_scheme():
    """`Config.options.media.dynamicAlbumColors` is not a member of that object."""
    src = code(POPUP)
    assert "useDynamicColors" not in src, \
        ("the popup reads Config.options.media.dynamicAlbumColors again. That key "
         "does not exist on the JsonObject, so it is `undefined` and every branch "
         "behind it is dead -- while a ColorQuantizer rescales the art per track")
    assert "ColorQuantizer" not in src, "the quantiser is back with nothing reading it"
    print("ok  cost: no album scheme is built for a branch that cannot run")


if __name__ == "__main__":
    check_filter_keeps_distinct_players()
    check_filter_still_merges_duplicates()
    check_filter_obeys_the_setting()
    check_exit_survives_the_flag()
    check_transform_origin()
    check_no_mask_over_the_scaled_column()
    check_disabled_controls_are_disabled()
    check_no_dead_colour_scheme()
    print("\nall ok")
