#!/usr/bin/env python3
"""Assert the fullscreen media player's card is still sized by its album art,
and that the surface still enters and leaves on two specs rather than one.

Neither of these has a symptom you can see in a still frame, which is why they
both shipped wrong.

The card used to be `min(540, width * 0.36)`. The album art inside it is square,
so on a 1920x1080 screen the art capped at 508 against 684 of available height
and ~180px of the card was void -- while the lyrics pane took 68% of the screen
to centre a 350px-wide line in it. Nothing failed: the layout rendered, the
checkers passed, the screenshot looked deliberate. The fix makes the card as
wide as the art can be tall, which only works while the art box is the one child
of the pane's layout that asks for no height of its own. Put a
`Layout.minimumHeight` back on it and the void returns silently.

The enter transition ran `opacity` and `contentScale` through one
`NumberAnimation` on one 500ms spatial curve, so the fade rode a spatial spec
(DESIGN 2.1) -- and the exit hand-computed `enterDuration / 2` with a curve
picked next to the `elementMoveExit` token that names both. Also invisible: the
surface animated either way.

Run: python3 tools/check-immersive-media.py
"""
import pathlib
import re
import sys

DIR = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii/modules/ii/immersiveMedia"
content = (DIR / "ImmersiveMediaContent.qml").read_text()
pane = (DIR / "ImmersiveNowPlayingPane.qml").read_text()

# --- structural: the shape the arithmetic below depends on --------------------

assert re.search(r"readonly property real chromeHeight: paneLayout\.implicitHeight", pane), \
    "the pane no longer measures its own chrome -- a hand-counted constant rots " \
    "the first time a row lands in this layout"

art_box = re.search(
    r"// ── Album art .*?\n(\s*Item \{.*?\n\1\})".replace(r"\1", r"        "),
    pane, re.S)
assert art_box, "the album art block is not where this check expects it"
art_box = art_box.group(1)

assert "Layout.fillHeight: true" in art_box, \
    "the album art box no longer takes the height that is left"
assert "Layout.preferredHeight: 0" in art_box, \
    "the album art box asks for height of its own, so it counts itself into " \
    "chromeHeight and the card comes out narrower than the art can be tall"
assert "Layout.minimumHeight" not in art_box, \
    "a minimum height on the art box is folded into the layout's implicitHeight " \
    "and therefore into chromeHeight -- the void this check exists for comes back"

# Every label in the card must elide rather than wrap, or its height starts
# depending on the card's width and the width binding becomes a real loop.
assert "wrapMode" not in pane, \
    "a label in the now-playing card wraps -- its height now depends on the card " \
    "width, which the card width is derived from. That is a binding loop"

# --- the arithmetic, lifted rather than transcribed ---------------------------

m = re.search(r"Layout\.preferredWidth: (Math\.min\(mediaRow\.height[^\n]*)", content)
assert m, "the now-playing card is no longer sized from the row height -- if that " \
          "is deliberate, this check is what has to change with it"
width_expr = m.group(1).strip()

MARGIN = 16          # ImmersiveMediaContent's ColumnLayout margins
GAP = 16             # its spacing, and the RowLayout's
TOOLBAR = 40         # ImmersiveMediaToolbar's icon buttons


def card_width(screen_w: int, screen_h: int, chrome: float, lyrics: bool) -> float:
    row_h = screen_h - MARGIN * 2 - TOOLBAR - GAP
    env = {
        "Math": type("M", (), {"min": staticmethod(min), "max": staticmethod(max)}),
        "mediaRow": type("R", (), {"height": row_h}),
        "nowPlaying": type("P", (), {"chromeHeight": chrome}),
        "root": type("C", (), {"width": screen_w, "lyricsShown": lyrics}),
    }
    return eval(width_expr.replace("?", "and").replace(" : ", " or "), {"__builtins__": {}}, env)


# `chromeHeight` is font- and player-dependent (title, artist, timestamps, the
# album pill, four 16dp gaps), so the invariants are swept over the band it can
# plausibly land in rather than pinned to one number.
SCREENS = [(1366, 768), (1600, 900), (1920, 1080), (2560, 1080), (2560, 1440),
           (3440, 1440), (3840, 2160), (1080, 1920)]
CHROME = range(240, 441, 20)

for w, h in SCREENS:
    for chrome in CHROME:
        for lyrics in (True, False):
            cap = w * (0.45 if lyrics else 0.6)
            card = card_width(w, h, chrome, lyrics)
            art_box_h = h - MARGIN * 2 - TOOLBAR - GAP - chrome
            art = min(card - MARGIN * 2, art_box_h)
            where = f"{w}x{h}, chrome={chrome}, lyrics={lyrics}"

            assert card <= cap + 0.5, \
                f"{where}: the card takes {card:.0f}px, past its {cap:.0f}px cap -- " \
                f"on a tall screen that squeezes the lyrics pane to nothing"

            if card < cap - 0.5:
                # Uncapped: the card is exactly the art, so neither axis has void.
                assert abs(art - (card - MARGIN * 2)) < 0.5 and abs(art - art_box_h) < 0.5, \
                    f"{where}: art {art:.0f} in a {card - 32:.0f}-wide, " \
                    f"{art_box_h:.0f}-tall box -- that is the void this check exists for"

            if lyrics:
                lyrics_w = w - MARGIN * 2 - GAP - card
                assert lyrics_w > card * 0.5, \
                    f"{where}: the lyrics pane is down to {lyrics_w:.0f}px against a " \
                    f"{card:.0f}px card"

# The card collapses once the row is shorter than the pane's own chrome. Nothing
# clamps that, deliberately -- but the screen it needs is one nobody runs, and
# that is the claim, not an accident.
worst_chrome = max(CHROME)
collapse_h = worst_chrome + MARGIN * 2 + TOOLBAR + GAP
assert collapse_h < 600, \
    f"the card collapses below {collapse_h}px of screen height, which is close " \
    f"enough to a real display to need a floor now"

# --- enter and exit ------------------------------------------------------------

shown = re.search(r"Transition \{\s*\n\s*to: \"shown\"(.*?)\n        \},", content, re.S)
hidden = re.search(r"Transition \{\s*\n\s*to: \"hidden\"(.*?)\n        \}\n    \]", content, re.S)
assert shown and hidden, "the surface no longer declares both an enter and an exit (DESIGN 2.5)"
shown, hidden = shown.group(1), hidden.group(1)

assert re.search(r"property: \"contentScale\"\s*\n\s*duration: Appearance\.animation\.elementMoveEnter", shown), \
    "the enter's scale is not on the default spatial spec -- it is the one thing " \
    "here allowed to overshoot (DESIGN 2.1)"
assert re.search(r"property: \"opacity\"\s*\n\s*duration: Appearance\.animation\.elementMoveFast", shown), \
    "the enter's opacity is not on an effects spec. One NumberAnimation over both " \
    "properties is what put the fade on a 500ms spatial curve"
assert re.search(r"duration: Appearance\.animation\.elementMoveExit\.duration", hidden) \
    and re.search(r"bezierCurve: Appearance\.animation\.elementMoveExit\.bezierCurve", hidden), \
    "the exit does not take both its duration and its curve from elementMoveExit -- " \
    "it used to hand-compute half the enter duration and pick a curve next to the " \
    "token that names both (DESIGN 2.5, rule 2)"
assert "root.closed()" in hidden, \
    "nothing tells the window it has left. ImmersiveMedia keeps a keyboard-grabbing " \
    "PanelWindow loaded until it hears this"

print("check-immersive-media: ok")
sys.exit(0)
