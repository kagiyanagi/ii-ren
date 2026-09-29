#!/usr/bin/env python3
"""Write assets/material-symbols.txt: every Material Symbols name the icon picker offers.

Two "Material Symbols Rounded" builds are installed here and Qt picks the older one, so a
name that only the newer build has renders as its literal text. The list is the names every
installed Rounded build shares, so nothing in the picker can come out as a word. Ligature
glyph names spell the separator ("underscore") and the digits ("digit_four"), and the
lookups sit in extension subtables.

Re-run after a font update: python3 tools/gen-material-symbols.py
"""
import glob
import pathlib
import re

from fontTools.ttLib import TTFont

OUT = pathlib.Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/assets/material-symbols.txt"


DIGITS = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
GLYPHS = {"underscore": "_", **{f"digit_{word}": str(n) for n, word in enumerate(DIGITS)}}


def names(path):
    found = set()

    def walk(table):
        if table is None:
            return
        if hasattr(table, "ExtSubTable"):
            return walk(table.ExtSubTable)
        for first, ligatures in getattr(table, "ligatures", {}).items():
            for ligature in ligatures:
                found.add("".join(GLYPHS.get(g, g) for g in [first, *ligature.Component]))

    for lookup in TTFont(path)["GSUB"].table.LookupList.Lookup:
        for table in lookup.SubTable:
            walk(table)
    # Only real icon names: lowercase words, digits and underscores.
    return {n for n in found if re.fullmatch(r"[a-z0-9_]+", n)}


fonts = glob.glob("/usr/share/fonts/**/MaterialSymbolsRounded*.ttf", recursive=True)
assert fonts, "no Material Symbols Rounded font installed"
shared = set.intersection(*(names(f) for f in fonts))
assert len(shared) > 3000, f"only {len(shared)} names; the ligature walk is broken"
OUT.write_text("\n".join(sorted(shared)) + "\n")
print(f"{len(shared)} names from {len(fonts)} font(s) -> {OUT}")
