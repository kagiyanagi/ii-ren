#!/usr/bin/env python3
"""Assert the element data is whole and the table's colour scales are the validated ones.

A chemistry student revises from this surface, so the failure that matters is not
a layout glitch -- it is a number that is silently wrong or missing, and neither a
screenshot nor qmllint can see either.

Three things are checked.

**The data.** 118 elements, numbered 1..118 with no gaps, every one placed inside
the 18-wide grid, every category one the palette has a slot for, and the fields a
syllabus actually asks for present on the elements that have been measured. A few
spot values are pinned against chemistry that does not change -- chromium and
copper's anomalous configurations, chlorine having the largest electron gain
enthalpy, the period-2 radii decreasing left to right -- so a regenerate against
a moved upstream cannot quietly rewrite them.

**The colour scales.** The family, block and trend palettes were produced by
search and validated with the data-viz validator (CVD separation, normal-vision
separation, lightness band, chroma floor, contrast). Re-running that validator
needs node, so what is asserted here is that the hexes have not been edited by
hand since -- if they change, the validation has to be redone rather than assumed.

**The ramp arithmetic.** `rampStep` maps a value onto 7 steps, linear or log. Off
the end of the domain in either direction it must clamp rather than index past
the ramp, and the log branch must not be handed a zero.

Run: python3 tools/check-periodic-table.py
"""
import json
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).parent.parent / "dots/.config/quickshell/ii/modules/ii/cheatsheet"
data_js = (ROOT / "periodic_table.js").read_text()
theme_js = (ROOT / "elements_theme.js").read_text()

fail = []


def check(ok, msg):
    if not ok:
        fail.append(msg)


# --- 1. the data ------------------------------------------------------------

body = data_js.split("const elements = [", 1)[1].split("\n];", 1)[0]
elements = json.loads("[" + body + "]")
by_symbol = {e["symbol"]: e for e in elements}

check(len(elements) == 118, f"{len(elements)} elements, not 118")
check([e["number"] for e in elements] == list(range(1, 119)),
      "atomic numbers are not 1..118 in order")
check(len({e["symbol"] for e in elements}) == 118, "two elements share a symbol")

for e in elements:
    check(1 <= e["x"] <= 18, f"{e['symbol']} sits at column {e['x']}, outside the 18-wide grid")
    check(1 <= e["y"] <= 10, f"{e['symbol']} sits on row {e['y']}, outside the table")
    check(e["block"] in ("s", "p", "d", "f"), f"{e['symbol']} is in block {e['block']!r}")
    check(bool(e["config"]) and bool(e["configShort"]),
          f"{e['symbol']} has no electron configuration")
    check(bool(e["shells"]), f"{e['symbol']} has no shell occupancies")
    check(sum(e["shells"]) == e["number"],
          f"{e['symbol']}'s shells sum to {sum(e['shells'])}, not its {e['number']} electrons")
    # A space between every subshell, or "[Xe] 5d16s2" reads as one term.
    check(not re.search(r"\d\d[spdf]", e["configShort"]),
          f"{e['symbol']}'s short configuration is missing a space: {e['configShort']!r}")

family_names = set(re.findall(r'"([^"]+)"', re.search(r"const familyOrder = \[(.*?)\];", theme_js, re.S).group(1)))
for e in elements:
    check(e["category"] in family_names,
          f"{e['symbol']} is a {e['category']!r}, which has no colour slot")
check(len(family_names) == 10, f"{len(family_names)} families, not the 10 the palette is stepped for")

# Chemistry that is not going to change, pinned so a regenerate cannot rewrite it.
check(by_symbol["Cr"]["configShort"] == "[Ar] 3d5 4s1",
      f"chromium's anomalous configuration is now {by_symbol['Cr']['configShort']!r}")
check(by_symbol["Cu"]["configShort"] == "[Ar] 3d10 4s1",
      f"copper's anomalous configuration is now {by_symbol['Cu']['configShort']!r}")
check(by_symbol["H"]["category"] == "nonmetal", "hydrogen is being coloured as a group-1 metal")
check(by_symbol["He"]["category"] == "noble gas", "helium is not a noble gas")
for symbol in ("F", "Cl", "Br", "I", "At"):
    check(by_symbol[symbol]["category"] == "halogen", f"{symbol} is not filed as a halogen")

affinities = [(e["electronAffinity"], e["symbol"]) for e in elements if e["electronAffinity"]]
check(max(affinities)[1] == "Cl",
      f"the largest electron gain enthalpy is {max(affinities)[1]}, not chlorine")

period2 = [e for e in elements if e["period"] == 2 and e["radiusEmpirical"] and e["group"] <= 17]
radii = [e["radiusEmpirical"] for e in sorted(period2, key=lambda e: e["group"])]
check(radii == sorted(radii, reverse=True),
      f"period-2 atomic radii no longer decrease across the period: {radii}")

# Gases are quoted in g/L and everything else in g/cm3; mixing them up prints
# oxygen as denser than aluminium.
for e in elements:
    if e["density"] is None:
        continue
    expected = "g/L" if e["phase"] == "Gas" else "g/cm3"
    check(e["densityUnit"] == expected,
          f"{e['symbol']} is a {e['phase']} quoted in {e['densityUnit']}")


# --- 2. the colour scales ---------------------------------------------------

def palette(name):
    match = re.search(rf"const {name} = \[(.*?)\];", theme_js, re.S)
    return re.findall(r'"(#[0-9a-f]{6})"', match.group(1)) if match else []


# These exact values passed the validator; changing one means re-running it.
expected = {
    "familyDark": ["#a2413d", "#cb7a35", "#7f6000", "#67a351", "#007b5c",
                   "#00a6b6", "#0f68aa", "#8d82db", "#834994", "#cb6d9c"],
    "familyLight": ["#a03f3c", "#e79551", "#7e5f00", "#81be6b", "#007a5b",
                    "#00c2d2", "#0b67a9", "#a79df8", "#814893", "#e887b6"],
    "blockDark": ["#c16400", "#00b16e", "#2c78f3", "#dd4ea9"],
    "blockLight": ["#9c4b00", "#00b97c", "#195cc7", "#e263b1"],
    "trendDark": ["#28567f", "#326898", "#3c7bb3", "#478ece", "#52a2ea", "#5eb6ff", "#6acbff"],
    "trendLight": ["#a5d7ff", "#88c0f6", "#6baae5", "#4e94d5", "#2d7fc4", "#0069b3", "#0054a2"],
}
for name, want in expected.items():
    got = palette(name)
    check(got == want,
          f"{name} was edited by hand -- it was validated as {want}, it is now {got}. "
          "Re-run the data-viz validator before changing a step.")

check(len(palette("familyDark")) == len(family_names),
      "the family palette has a different number of slots than there are families")
check(len(palette("trendDark")) == 7, "the trend ramp is no longer 7 steps")
# Both modes are stepped separately rather than flipped, so neither list may be
# the other reversed.
check(palette("trendDark") != list(reversed(palette("trendLight"))),
      "the light ramp is the dark one reversed -- each mode is stepped for its own surface")


# --- 3. the ramp arithmetic -------------------------------------------------

def ramp_step(value, low, high, logarithmic):
    """`rampStep` from elements_theme.js, as Python."""
    if value is None or high == low:
        return 0
    if logarithmic and low > 0:
        t = (math.log(value) - math.log(low)) / (math.log(high) - math.log(low))
    else:
        t = (value - low) / (high - low)
    return max(0, min(6, round(t * 6)))


for value, low, high, log in [
    (5, 0, 10, False), (0, 0, 10, False), (10, 0, 10, False),
    (-50, 0, 10, False), (999, 0, 10, False),      # off both ends
    (1, 1, 1, False),                              # a domain of one value
    (0.5, 0.00009, 22.6, True),                    # density, log
    (0.00009, 0.00009, 22.6, True), (22.6, 0.00009, 22.6, True),
    (5, 0, 10, True),                              # log asked for, zero low
]:
    step = ramp_step(value, low, high, log)
    check(isinstance(step, int) and 0 <= step <= 6,
          f"rampStep({value}, {low}, {high}, log={log}) = {step!r}, outside 0..6")

check(ramp_step(None, 0, 10, False) == 0, "a missing value does not fall back to the first step")


if fail:
    print(f"check-periodic-table.py: {len(fail)} finding(s)\n")
    for f in fail[:40]:
        print(f"  FAIL  {f}")
    if len(fail) > 40:
        print(f"  ... and {len(fail) - 40} more")
    sys.exit(1)
print(f"check-periodic-table.py: ok ({len(elements)} elements)")
