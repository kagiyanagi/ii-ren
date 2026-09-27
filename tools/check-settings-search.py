#!/usr/bin/env python3
"""Settings search lands on the page it found the result on.

Every settings page declares `readonly property int index: N`, and that number is
the only thing search navigates by: SearchRegistry reads it out of the file text
for the statically indexed pages, and ContentSection reads it at runtime for the
rest. It is not derived from anything. settings.qml's `pages` array was reordered
and six of the numbers were not, so a search for "Fonts" opened Services, every
Interface result opened Widgets and every Lock result opened About, with no error:
the page loads, it is just the wrong one. This pins each declared index to the
page's position in `pages`, and the static index list to files that exist.

ContentSection also skipped registration on `!ownerPage.index`, which is true for
page 0. And nothing sets `register` anyway, so the runtime path never runs: the
static list in SearchRegistry is the whole of search, and it named six of twelve pages.
"""
import pathlib, re, subprocess, sys

SHELL = pathlib.Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
settings = (SHELL / "settings.qml").read_text()
pages = re.findall(r'component:\s*"(modules/settings/\w+\.qml)"', settings)
assert len(pages) >= 10, f"could not read the pages array out of settings.qml ({pages})"

bad = []
for i, rel in enumerate(pages):
    src = (SHELL / rel).read_text()
    # The same regex SearchRegistry.extractPageIndex uses: the first match wins.
    m = re.search(r"readonly\s+property\s+int\s+index\s*:\s*(\d+)", src)
    if m is None:
        continue  # a page without one is simply not searchable (About)
    if int(m.group(1)) != i:
        bad.append(f"{rel}: declares index {m.group(1)}, is page {i} in settings.qml")
assert not bad, "settings search would open the wrong page:\n  " + "\n  ".join(bad)

# SearchRegistry reads every page's text; that is the only way into search, since
# nothing in the settings app sets the `register` flag that ContentSection's
# runtime registration waits on. Six pages were missing from its list.
registry = (SHELL / "services/SearchRegistry.qml").read_text()
m = re.search(r"indexedPages:\s*\[(.*?)\]", registry, re.S)
assert m, "SearchRegistry no longer declares indexedPages"
indexed = {f"modules/settings/{n}.qml" for n in re.findall(r'"(\w+)"', m.group(1))}
for rel in indexed:
    assert (SHELL / rel).exists(), f"SearchRegistry indexes {rel}, which does not exist"
    assert rel in pages, f"SearchRegistry indexes {rel}, which is not a page"
for rel in pages:
    has_index = re.search(r"readonly\s+property\s+int\s+index\s*:", (SHELL / rel).read_text())
    if has_index:
        assert rel in indexed, f"{rel} declares a search index but SearchRegistry never reads it"

# The static index finds sections by brace matching over the file text. It treated
# an apostrophe in a `//` comment as a string quote, and everything after it was one
# unterminated string: Quick indexed one section of three and Hermes four of six.
# Run the real extractBlocks under node and compare with a line count.
fn = registry[registry.index("    function extractBlocks"):registry.index("    // Helper function for indexQmlFile(), extracts properties")]
js = fn.replace("    function extractBlocks", "function extractBlocks", 1) + """
const fs = require('fs');
const out = {};
for (const f of process.argv.slice(1)) out[f] = extractBlocks(fs.readFileSync(f, 'utf8'), 'ContentSection').length;
console.log(JSON.stringify(out));
"""
files = [str(SHELL / rel) for rel in sorted(indexed)]
counts = __import__("json").loads(subprocess.run(["node", "-e", js, *files], capture_output=True, text=True, check=True).stdout)
for f in files:
    code = re.sub(r"//[^\n]*", "", pathlib.Path(f).read_text())
    declared = len(re.findall(r"\bContentSection\s*\{", code))
    assert counts[f] == declared, f"{pathlib.Path(f).name}: search indexes {counts[f]} of {declared} sections"

section = (SHELL / "modules/common/widgets/ContentSection.qml").read_text()
assert "if (!ownerPage.index)" not in section, "ContentSection skips page 0 again"

print(f"ok: {len(pages)} settings pages, every declared search index matches its position")
