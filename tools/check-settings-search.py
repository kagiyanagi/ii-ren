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
page 0, so nothing on the Quick page was ever searchable.
"""
import pathlib, re, sys

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

# The files SearchRegistry indexes statically, by path, from Directories.
dirs = (SHELL / "modules/common/Directories.qml").read_text()
static = re.findall(r"quickshell/ii/(modules/settings/\w+\.qml)", dirs)
assert static, "no statically indexed settings pages found in Directories.qml"
for rel in static:
    assert (SHELL / rel).exists(), f"SearchRegistry indexes {rel}, which does not exist"
    assert rel in pages, f"SearchRegistry indexes {rel}, which is not a page"

section = (SHELL / "modules/common/widgets/ContentSection.qml").read_text()
assert "if (!ownerPage.index)" not in section, "ContentSection skips page 0 again"

print(f"ok: {len(pages)} settings pages, every declared search index matches its position")
