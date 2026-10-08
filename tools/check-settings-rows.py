#!/usr/bin/env python3
"""Settings pages keep one card layout, and the chip rows cannot spin the app.

The redesign of 2026-10-08 put every label inside its card: a control too wide
to sit beside its label is a `ConfigLabeledRow` (or `ConfigSelectionRow` for
chips), never a `ContentSubsection` header floating over a bare control, which
left each such choice 8px in from the switch rows around it at a width of its
own. This gate fails on the old shape coming back.

It also guards the freeze found on the way. A `ConfigSelectionArray` is a
`Flow`, and a Flow reports the width of its chips on one line, which changes as
it wraps. Inside a page sized to its content (`ContentPage { forceWidth: false
}`) that width fed back: the page widened to fit the line, the chips wrapped
inside the row's insets, the page shrank, they unwrapped -- 100% CPU, measured
on the Weather options page. Two things break the loop, and both are checked:
`ConfigSelectionRow` asks for no width of its own (`Layout.preferredWidth: 0`),
and every settings page has a fixed width (`forceWidth: true`).

    python3 tools/check-settings-rows.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHELL = ROOT / "dots/.config/quickshell/ii"
SETTINGS = SHELL / "modules/settings"
WIDGETS = SHELL / "modules/common/widgets"

# A subsection whose only child is one of these is a header floating over a
# bare control.
BARE = {"ConfigSelectionArray", "StyledComboBox", "MaterialTextField", "MaterialTextArea"}


def block_end(lines, i):
    depth = 0
    for j in range(i, len(lines)):
        text = re.sub(r"(^|\s)//.*$", "", lines[j])
        depth += sum(text.count(c) for c in "{[(") - sum(text.count(c) for c in "}])")
        if depth == 0:
            return j
    raise ValueError(f"unbalanced block at line {i + 1}")


def children(lines, i, end):
    """Type names of the direct child objects of the block opened at line i."""
    indent = len(lines[i]) - len(lines[i].lstrip()) + 4
    found, j = [], i + 1
    while j < end:
        line = lines[j]
        if line.strip() and len(line) - len(line.lstrip()) == indent:
            m = re.match(r"\s*([A-Z][A-Za-z.]*)\s*\{\s*$", line)
            if m:
                found.append(m.group(1))
            j = block_end(lines, j) + 1
            continue
        j += 1
    return found


def main():
    failures = []
    pages = sorted(SETTINGS.glob("*.qml")) + sorted(SETTINGS.glob("widgets/*.qml")) + [SHELL / "welcome.qml"]

    for path in pages:
        lines = path.read_text().split("\n")
        rel = path.relative_to(SHELL)
        for i, line in enumerate(lines):
            if line.strip() != "ContentSubsection {":
                continue
            kids = children(lines, i, block_end(lines, i))
            if len(kids) == 1 and kids[0] in BARE:
                failures.append(f"{rel}:{i + 1}: ContentSubsection over a bare {kids[0]}; "
                                f"use ConfigLabeledRow / ConfigSelectionRow")
        text = "\n".join(lines)
        if re.search(r"^ContentPage \{", text, re.M) and "forceWidth: false" in text:
            failures.append(f"{rel}: forceWidth: false lets a chip row size the page and spin it")

    row = (WIDGETS / "ConfigSelectionRow.qml").read_text()
    if not re.search(r"ConfigSelectionArray \{[^}]*Layout\.preferredWidth: 0", row, re.S):
        failures.append("ConfigSelectionRow.qml: the chip array must ask for no width "
                        "(Layout.preferredWidth: 0), or its wrap feeds back into the page")

    # A row's label and its chips share the card's inset: the array's own
    # padding is zeroed because the row's body already carries it.
    for prop in ("leftPadding: 0", "rightPadding: 0"):
        if prop not in row:
            failures.append(f"ConfigSelectionRow.qml: chip array lost `{prop}`, chips drift off the label column")

    if failures:
        print("\n".join(failures))
        sys.exit(1)
    print(f"ok: {len(pages)} settings files keep labels in their cards, "
          f"and no chip row can size its page")


if __name__ == "__main__":
    main()
