#!/usr/bin/env python3
"""Generate the cheatsheet's element data from two public datasets.

Nothing in `periodic_table.js` is typed by hand. A chemistry student is going to
revise from these numbers, so every one of them is traceable to a source and the
two sources are cross-checked against each other where they overlap -- a silent
disagreement in electronegativity or a melting point is exactly the kind of
error a screenshot review cannot catch.

Sources, both fetched at generation time and not vendored as inputs:

- Bowserinator/Periodic-Table-JSON (CC-BY-SA 3.0, from Wikipedia) for electron
  configurations, shell occupancies, the full ionisation-energy series, phase,
  melting/boiling points, density, molar heat, appearance and the summary text.
- andrejewski/periodic-table (PubChem-derived) for ionic radius, oxidation
  states, bonding type and year of discovery -- the fields the first one does
  not carry and which 11th/12th and JEE syllabi lean on hardest.
- Wikipedia's "Atomic radii of the elements (data page)" for the radii
  themselves, parsed out of the page's one wikitable. The PubChem radius column
  is blank for Ce through Yb and for every actinide, which is precisely the
  stretch a student is looking at when they are learning the lanthanide
  contraction; this table covers all 118 and carries empirical, calculated,
  covalent, metallic and van der Waals values separately, which is more useful
  than one unlabelled "atomic radius" anyway.

Categories are re-derived rather than taken from either source: Bowserinator
files every halogen under "diatomic nonmetal", and a periodic table that does
not colour group 17 as its own family is not much use to someone learning
group trends.

Run: python3 tools/gen-periodic-table.py [--offline]
"""
import argparse
import csv
import io
import json
import pathlib
import html
import re
import sys
import urllib.request

OUT = (pathlib.Path(__file__).parent.parent
       / "dots/.config/quickshell/ii/modules/ii/cheatsheet/periodic_table.js")
CACHE = pathlib.Path("/tmp/claude-1000/periodic-table-sources")

BOWSERINATOR = "https://raw.githubusercontent.com/Bowserinator/Periodic-Table-JSON/master/PeriodicTableJSON.json"
ANDREJEWSKI = "https://raw.githubusercontent.com/andrejewski/periodic-table/master/data.csv"
WIKI_RADII = "https://en.wikipedia.org/wiki/Atomic_radii_of_the_elements_(data_page)"

# The seven elements every syllabus calls metalloids. Bowserinator agrees on six
# of them and files At as a halogen, which is the more useful call here.
METALLOIDS = {5, 14, 32, 33, 51, 52, 84}


def fetch(url: str, name: str, offline: bool) -> str:
    CACHE.mkdir(parents=True, exist_ok=True)
    cached = CACHE / name
    if offline or cached.exists():
        if not cached.exists():
            sys.exit(f"--offline but {cached} is not there; run once with network")
        return cached.read_text()
    with urllib.request.urlopen(url, timeout=60) as response:  # noqa: S310 - fixed https URLs
        text = response.read().decode()
    cached.write_text(text)
    return text


def parse_wiki_radii(page: str):
    """The data page's single wikitable -> {atomic number: {radius kind: pm}}.

    Cells carry footnote markers and the occasional "182[3] or 181[4]", so the
    first integer in the cell is the value and the rest is provenance.
    """
    tables = re.findall(r"<table[^>]*wikitable[^>]*>.*?</table>", page, re.S)
    assert len(tables) == 1, f"the radii data page has {len(tables)} wikitables, not 1"
    kinds = ["empirical", "calculated", "vdw", "covalent", "covalentTriple", "metallic"]
    out = {}
    for row in re.findall(r"<tr[^>]*>(.*?)</tr>", tables[0], re.S):
        cells = [html.unescape(re.sub(r"<[^>]+>", "", c)).strip()
                 for c in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S)]
        if len(cells) < 4 or not cells[0].isdigit():
            continue
        values = {}
        for kind, cell in zip(kinds, cells[3:9]):
            found = re.search(r"\d+", cell)
            if found:
                values[kind] = int(found.group())
        out[int(cells[0])] = values
    return out


def category_of(number: int, group: int, block: str) -> str:
    """Families as a syllabus draws them, not as either source files them."""
    if 57 <= number <= 71:
        return "lanthanide"
    if 89 <= number <= 103:
        return "actinide"
    if number == 1:
        return "nonmetal"
    if group == 1:
        return "alkali metal"
    if group == 2:
        return "alkaline earth metal"
    if group == 17:
        return "halogen"
    if group == 18:
        return "noble gas"
    if number in METALLOIDS:
        return "metalloid"
    if block == "d":
        return "transition metal"
    if block == "p":
        # What is left of the p block splits on the metalloid staircase.
        return "post-transition metal" if number in {
            13, 31, 49, 50, 81, 82, 83, 113, 114, 115, 116
        } else "nonmetal"
    return "post-transition metal"


def number_or_none(value):
    if value is None:
        return None
    text = str(value).strip()
    if not text or text.lower() in {"n/a", "none", ""}:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def parse_oxidation_states(text: str):
    """"-2, -1, 1, 2, 3" -> [-2, -1, 1, 2, 3]. Blank means the source has none."""
    if not text or not text.strip():
        return []
    out = []
    for part in text.split(","):
        part = part.strip()
        if re.fullmatch(r"[+-]?\d+", part):
            out.append(int(part))
    return sorted(set(out))


def clean(text):
    if text is None:
        return None
    text = str(text).strip()
    return text or None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--offline", action="store_true",
                        help="use the cached downloads instead of fetching")
    args = parser.parse_args()

    wiki = json.loads(fetch(BOWSERINATOR, "bowserinator.json", args.offline))["elements"]
    radii = parse_wiki_radii(fetch(WIKI_RADII, "wiki-radii.html", args.offline))
    rows = list(csv.DictReader(io.StringIO(fetch(ANDREJEWSKI, "andrejewski.csv", args.offline))))
    pub = {}
    for row in rows:
        row = {k.strip(): (v.strip() if isinstance(v, str) else v) for k, v in row.items()}
        pub[int(row["atomicNumber"])] = row

    elements = []
    disagreements = []

    for entry in wiki:
        number = entry["number"]
        if number > 118:  # 119 is predicted, not discovered
            continue
        other = pub.get(number, {})
        radius = radii.get(number, {})

        group = entry.get("group")
        block = entry.get("block")
        mass = entry.get("atomic_mass")

        # Cross-check the fields both sources carry. Radii and oxidation states
        # come from one source only, so they cannot be checked this way -- which
        # is worth knowing when reading them.
        for field, mine, theirs, tolerance in [
            ("electronegativity", entry.get("electronegativity_pauling"),
             number_or_none(other.get("electronegativity")), 0.06),
            ("melt", entry.get("melt"), number_or_none(other.get("meltingPoint")), 2.0),
            ("boil", entry.get("boil"), number_or_none(other.get("boilingPoint")), 2.0),
            ("density", entry.get("density"), number_or_none(other.get("density")), 0.05),
        ]:
            if mine is None or theirs is None:
                continue
            # Not a disagreement: Wikipedia quotes a gas density in g/L and
            # PubChem in g/cm3, so the two differ by exactly 1000. Getting this
            # wrong would print oxygen at 1.429 g/cm3, which is denser than
            # aluminium.
            if field == "density" and 0.98 < (float(mine) / 1000) / float(theirs) < 1.02:
                continue
            if abs(float(mine) - float(theirs)) > tolerance:
                disagreements.append(f"{number:3d} {entry['symbol']:2s} {field}: "
                                     f"wikipedia {mine} vs pubchem {theirs}")

        ionisation = [round(v, 1) for v in (entry.get("ionization_energies") or [])]

        elements.append({
            "number": number,
            "symbol": entry["symbol"],
            "name": entry["name"],
            # Grid position as the standard 18-wide layout draws it, f block on
            # its own two rows underneath.
            "x": entry["xpos"],
            "y": entry["ypos"],
            "category": category_of(number, group, block),
            "block": block,
            "group": group,
            "period": entry.get("period"),
            "mass": round(mass, 4) if mass else None,
            "config": clean(entry.get("electron_configuration")),
            # Lanthanum ships as "[Xe] 5d16s2" upstream, missing one space.
            "configShort": re.sub(r"(\d)(\d[spdf])", r"\1 \2",
                                  clean(entry.get("electron_configuration_semantic")) or ""),
            "shells": entry.get("shells") or [],
            "electronegativity": entry.get("electronegativity_pauling"),
            # kJ/mol. Bowserinator's electron_affinity is already the enthalpy
            # released, i.e. the positive-is-exothermic convention.
            "electronAffinity": entry.get("electron_affinity"),
            "ionisation": ionisation[:4],
            # All pm. Empirical is the one a textbook means by "atomic radius";
            # the others are there because which one is meaningful depends on
            # the element -- covalent for a nonmetal, metallic for a metal, van
            # der Waals for a noble gas.
            "radiusEmpirical": radius.get("empirical"),
            "radiusCalculated": radius.get("calculated"),
            "radiusCovalent": radius.get("covalent"),
            "radiusMetallic": radius.get("metallic"),
            "radiusVdw": radius.get("vdw"),
            "ionRadius": clean(other.get("ionRadius")),
            "oxidationStates": parse_oxidation_states(other.get("oxidationStates", "")),
            "phase": clean(entry.get("phase")),
            "melt": entry.get("melt"),
            "boil": entry.get("boil"),
            "density": entry.get("density"),
            # g/L for anything gaseous at room temperature, g/cm3 otherwise --
            # the convention the Wikipedia tables use, and the reason the two
            # sources look like they disagree by a factor of 1000 on the gases.
            "densityUnit": "g/L" if clean(entry.get("phase")) == "Gas" else "g/cm3",
            "molarHeat": entry.get("molar_heat"),
            "bonding": clean(other.get("bondingType")),
            "appearance": clean(entry.get("appearance")),
            "discoveredBy": clean(entry.get("discovered_by")),
            "year": clean(other.get("yearDiscovered")),
            "summary": clean(entry.get("summary")),
        })

    elements.sort(key=lambda e: e["number"])
    assert len(elements) == 118, f"expected 118 elements, built {len(elements)}"
    assert [e["number"] for e in elements] == list(range(1, 119)), "atomic numbers are not 1..118"

    body = ",\n".join("    " + json.dumps(e, ensure_ascii=False, sort_keys=True) for e in elements)
    OUT.write_text(f"""\
// Generated by tools/gen-periodic-table.py -- do not edit by hand.
//
// A chemistry student revises from these numbers, so none of them were typed
// here. Sources, cross-checked against each other where they overlap:
//   Bowserinator/Periodic-Table-JSON  (CC-BY-SA 3.0, from Wikipedia)
//     configurations, shells, ionisation series, phase, mp/bp, density,
//     molar heat, appearance, summary
//   andrejewski/periodic-table        (PubChem-derived)
//     atomic / ionic / van der Waals radii, oxidation states, bonding, year
//
// Radii, oxidation states and the ionisation series past the first value come
// from one source each and so are not cross-checked. Values differ between
// textbooks; these are the PubChem and Wikipedia ones.
//
// Categories are re-derived in the generator, not taken from either source:
// group 17 is its own family here, which is how a syllabus draws it.

.pragma library

const elements = [
{body}
];

const byNumber = {{}};
const bySymbol = {{}};
for (let i = 0; i < elements.length; i++) {{
    byNumber[elements[i].number] = elements[i];
    bySymbol[elements[i].symbol.toLowerCase()] = elements[i];
}}
""", encoding="utf-8")

    print(f"{OUT.relative_to(pathlib.Path(__file__).parent.parent)}: "
          f"{len(elements)} elements, {OUT.stat().st_size // 1024} KiB")
    if disagreements:
        print(f"\n{len(disagreements)} value(s) the two sources disagree on "
              f"(Wikipedia wins; listed so they can be eyeballed):")
        for line in disagreements:
            print("  " + line)


if __name__ == "__main__":
    main()
