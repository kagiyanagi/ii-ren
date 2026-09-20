#!/usr/bin/env python3
"""Assert a carded config row's own film matches the card behind it.

`ContentGroup` draws the card for every settings row that sets `wantsCard`. That
card is 8px wider than the row per side (`horizontalBleed`) and rounds the ends
of a run harder than its seams, so a row that paints anything of its own -- the
search-highlight flash, a focus film -- has to take *both* the card's four
corner radii and its per-side reach, or the fill stops short of the card's edges
and squares off corners the card rounds (DESIGN.md 5.6, 10.13).

ContentGroup only hands those over to a row that exposes `buttonRadius`. That
handshake is the whole mechanism and it is invisible when broken: these films sit
at opacity 0 except for the three blinks of a search hit, so a regression ships
and nobody sees it until someone searches for that one setting.

check-design.py cannot see any of it -- there is no literal to flag, only an
`anchors.fill` where four radii should be.

Run: python3 tools/check-config-row-cards.py
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii/modules/common/widgets"

CORNERS = ("topLeftRadius", "topRightRadius", "bottomLeftRadius", "bottomRightRadius")
FILMS = ("HighlightOverlay", "StateOverlay")


def block_at(src: str, start: int) -> str:
    """The braced body beginning at the first `{` at or after `start`."""
    open_at = src.index("{", start)
    depth = 0
    for i in range(open_at, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[open_at:i + 1]
    raise AssertionError("unbalanced braces")


# The card's side of the handshake. If cw-scaffolding renames either half, every
# row below silently goes back to painting a slab that disagrees with its card.
group = (ROOT / "ContentGroup.qml").read_text()
assert "buttonRadius !== undefined" in group, \
    "ContentGroup no longer keys the per-tile radii off buttonRadius -- the rows below expect it"
assert re.search(r'property:\s*"backgroundBleedLeft"', group) and \
       re.search(r'property:\s*"backgroundBleedRight"', group), \
    "ContentGroup no longer hands rows a per-side bleed -- the rows below expect it"
for corner in CORNERS:
    assert f'property: "{corner}"' in group, \
        f"ContentGroup no longer hands rows {corner} -- the rows below expect it"

rows = sorted(p for p in ROOT.glob("Config*.qml") if "wantsCard" in p.read_text())
assert len(rows) >= 7, f"only {len(rows)} carded config rows found -- did the family move?"

checked = 0
for path in rows:
    src = path.read_text()
    # Comments mention these property names while explaining them; only the code
    # counts.
    code = re.sub(r"//.*$", "", src, flags=re.M)
    name = path.name

    for film in FILMS:
        for m in re.finditer(rf"\b{film}\s*\{{", src):
            body = block_at(src, m.start())

            # A film that never paints has nothing to match. ConfigSlider keeps one
            # purely as an opacity source for its label; it is not a card fill.
            if re.search(r"^\s*visible:\s*false\s*$", body, re.M):
                continue

            checked += 1
            where = f"{name}: {film}"

            # The row has to be the card's tile, or ContentGroup never drives any of
            # this. RippleButton-rooted rows inherit buttonRadius from the root.
            assert re.search(r"\bbuttonRadius\b", code), (
                f"{where} paints over its card but the row exposes no buttonRadius -- "
                f"ContentGroup will not hand it the card's radii or bleed")

            assert "anchors.fill" not in body, (
                f"{where} uses anchors.fill -- the card reaches 8px further per side, "
                f"so the film has to be sized from backgroundBleedLeft/Right instead")

            for corner in CORNERS:
                assert corner in body, (
                    f"{where} does not take the card's {corner} -- a single radius "
                    f"squares off the corners a run end rounds")

            for side in ("backgroundBleedLeft", "backgroundBleedRight"):
                assert side in body, (
                    f"{where} does not take {side} -- the fill stops 8px short of the "
                    f"card's edge on that side")

assert checked >= 3, f"only {checked} painting films found across {len(rows)} rows -- did they move?"
print(f"ok: {checked} card fills across {len(rows)} carded config rows match their card's geometry")
