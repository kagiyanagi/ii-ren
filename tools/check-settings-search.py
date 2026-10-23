#!/usr/bin/env python3
"""Settings search finds every setting, and lands on it.

Search reads the settings pages as text: services/settingsSearch.js parses each
page, and every sub-page a page opens, into its object tree, and each row with a
static label is a result of its own that knows its page, sub-page and section.
It used to be regexes over the page text that took section titles, switches and
spin boxes, never a sub-page, and summed loose letter-subsequence scores per
section. "Shake to find the pointer" lives on Advanced > Cursor, a sub-page, so
it could not be found at all; the owner had to ask an AI where the switch was.

This runs the real indexer under node over the real files, the way
SearchRegistry.qml reads them, and holds:

- every row whose label a plain regex can read is in the index. The reader once
  took an apostrophe in a comment for a quote and lost every section after it;
- every sub-page a page opens, and every widget's config page, is indexed;
- queries people actually typed, typos and filler words included, put the right
  row first;
- every row type the index lists can be landed on: its widget, or the one it
  derives from, has a SearchHandler, and sections declare the scope it reads.
"""
import json, pathlib, re, subprocess

SHELL = pathlib.Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
WIDGETS = SHELL / "modules/common/widgets"

settings = (SHELL / "settings.qml").read_text()
pages = [{"id": m.group(1), "component": m.group(2)}
         for m in re.finditer(r'id:\s*"(\w+)",[^}]*?component:\s*"(modules/settings/\w+\.qml)"', settings, re.S)]
assert len(pages) >= 10, f"could not read the pages array out of settings.qml ({pages})"
assert "SearchRegistry.index(root.pages)" in settings, "settings.qml no longer hands its pages to search"

registry = (SHELL / "services/SearchRegistry.qml").read_text()
sources = dict(re.findall(r'"(\w+)":\s*"([^"]+\.qml)"', registry[registry.index("subPageSources"):]))
for page_id, path in sources.items():
    assert any(p["id"] == page_id for p in pages), f"SearchRegistry.subPageSources names a page that is not one: {page_id}"
    assert (SHELL / path).exists(), f"SearchRegistry.subPageSources reads {path}, which does not exist"

# The same plan SearchRegistry's reader follows, run on the real indexer.
driver = r"""
const fs = require('fs');
const S = require(process.argv[1] + '/services/settingsSearch.js');
const shell = process.argv[1];
const pages = JSON.parse(process.argv[2]);
const sources = JSON.parse(process.argv[3]);
const queries = JSON.parse(process.argv[4]);
const entries = [];
const files = [];
pages.forEach((page, i) => {
    const text = fs.readFileSync(shell + '/' + page.component, 'utf8');
    files.push({ path: page.component, page: i, subPage: '' });
    let subs = S.subPagesOf(text);
    if (sources[page.id])
        subs = subs.concat(S.subPagesOf(fs.readFileSync(shell + '/' + sources[page.id], 'utf8')));
    for (const sub of [...new Set(subs)])
        files.push({ path: 'modules/settings/' + sub, page: i, subPage: sub });
});
for (const f of files) {
    const found = S.indexFile(fs.readFileSync(shell + '/' + f.path, 'utf8'), f.subPage);
    found.forEach(e => { e.page = f.page; e.file = f.path; });
    entries.push(...found);
}
const index = S.buildIndex(entries, pages.map(p => ({ name: p.id })));
const results = {};
for (const q of queries)
    results[q] = S.search(index, q, 10).map(r => ({ label: r.label, page: pages[r.entry.page].id, subPage: r.entry.subPage }));
console.log(JSON.stringify({ files, entries, results }));
"""

QUERIES = {
    # The owner's own query, typo and all, for a switch on a sub-page.
    "shake to find cursiror": ("Shake to find the pointer", "advanced", "widgets/CustomCursorConfig.qml"),
    # Filler words are not required to match.
    "turn off shake to find": ("Shake to find the pointer", "advanced", "widgets/CustomCursorConfig.qml"),
    "earbang": ("Earbang protection", "general", ""),
    "dock height": ("Dock height", "interface", ""),
    # A slip in a long word.
    "wallpapr": ("Wallpaper", "background", ""),
}

out = subprocess.run(["node", "-e", driver, str(SHELL), json.dumps(pages), json.dumps(sources), json.dumps(list(QUERIES) + ["shake"])],
                     capture_output=True, text=True)
assert out.returncode == 0, out.stderr
data = json.loads(out.stdout)
files, entries, results = data["files"], data["entries"], data["results"]

# Every sub-page is read: the ones pages open, and the widget gallery's.
indexed_files = {e["file"] for e in entries}
for f in files:
    assert (SHELL / f["path"]).exists(), f"{f['path']} is opened as a sub-page and does not exist"
widget_pages = {f"modules/settings/{m}" for m in re.findall(r'"configPage":\s*"(widgets/\w+\.qml)"',
                (SHELL / "modules/ii/background/widgets/WidgetsRegistry.qml").read_text())}
assert widget_pages, "read no widget config pages out of WidgetsRegistry.qml"
missing = sorted(widget_pages - {f["path"] for f in files})
assert not missing, f"widget config pages search never reads: {missing}"
assert "modules/settings/widgets/CustomCursorConfig.qml" in indexed_files, "the Cursor sub-page is not indexed"

# What a plain regex can read is the floor: a row type, its `{`, then a static
# text: before anything nested. The parser must find every one.
row_types = re.search(r"var ROW_TYPES = \{(.*?)\};", (SHELL / "services/settingsSearch.js").read_text(), re.S)
row_types = re.findall(r"(\w+):", row_types.group(1))
assert "ConfigSwitch" in row_types and "ConfigNavRow" in row_types, row_types
row_re = re.compile(r"\b(?:" + "|".join(row_types) + r")\s*\{([^{}]*)")
label_re = re.compile(r'^\s*text:\s*Translation\.tr\("((?:[^"\\]|\\.)+)"\)\s*;?\s*$', re.M)
by_file = {}
for e in entries:
    by_file.setdefault(e["file"], set()).add(e["label"])
lost = []
floor = 0
for f in files:
    code = re.sub(r"(?m)^\s*//.*$", "", (SHELL / f["path"]).read_text())
    for block in row_re.findall(code):
        m = label_re.search(block)
        if not m or "%" in m.group(1):
            continue
        floor += 1
        if m.group(1) not in by_file.get(f["path"], set()):
            lost.append(f"{f['path']}: {m.group(1)}")
assert floor > 300, f"the regex floor read only {floor} rows; it is checking nothing"
assert not lost, "rows the search index lost:\n  " + "\n  ".join(lost[:20])

for query, (label, page, sub) in QUERIES.items():
    got = results[query]
    assert got, f"{query!r} finds nothing"
    top = got[0]
    assert top["label"].startswith(label) and top["page"] == page and top["subPage"] == sub, \
        f"{query!r} puts {top} first, not {label!r} on {page} {sub}"
assert not any(r["label"] == "Shape" for r in results["shake"]), "\"shake\" reads as a typo of \"Shape\" again"

# A result lands only where a SearchHandler is waiting for it.
def handles_search(name, seen=()):
    path = WIDGETS / f"{name}.qml"
    if not path.exists() or name in seen:
        return False
    src = path.read_text()
    if "SearchHandler {" in src:
        return True
    base = re.search(r"^(\w+)\s*\{", re.sub(r"(?m)^(import|pragma|//).*$", "", src), re.M)
    return bool(base) and handles_search(base.group(1), seen + (name,))
for t in row_types + ["ContentSection", "ContentSubsection"]:
    assert handles_search(t), f"{t} is indexed but has no SearchHandler, so opening it lands nowhere"
for t, scope in [("ContentSection", "section"), ("ContentSubsection", "subsection")]:
    assert f'readonly property string searchScope: "{scope}"' in (WIDGETS / f"{t}.qml").read_text(), \
        f"{t} no longer declares the searchScope SearchHandler reads its section from"

print(f"ok: {len(entries)} settings indexed from {len(indexed_files)} files, {len(QUERIES) + 1} queries land")
