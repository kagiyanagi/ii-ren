#!/usr/bin/env python3
"""StyledListView turns its transitions off with `enabled`, not by emptying them.

With `animateAppearance: false` the transitions used to stay set, with an empty
animation list. ListView still treats an empty transition as one to run, and
under a burst of model changes in one turn -- a Wi-Fi scan or a Bluetooth
discovery landing through a ScriptModel -- it lost track of removed rows: they
stayed drawn over the live rows, their object destroyed, so the Wi-Fi dialog
showed "Unknown / Connecting…" on top of real networks. A plain ListView on the
same model never did. Seen only by watching the shell, so this pins the shape.
"""
import pathlib, re

qml = (pathlib.Path(__file__).resolve().parent.parent
       / "dots/.config/quickshell/ii/modules/common/widgets/StyledListView.qml").read_text()

gate = {
    "add": "animateAppearance",
    "addDisplaced": "animateAppearance",
    "remove": "animateAppearance",
    "removeDisplaced": "animateAppearance",
    "displaced": "animateMovement",
    "move": "animateMovement",
    "moveDisplaced": "animateMovement",
}
for name, flag in gate.items():
    m = re.search(rf"\n    {name}: Transition \{{\s*\n\s*enabled: root\.(\w+)\n", qml)
    assert m, f"{name}: Transition does not open with `enabled: root.{flag}`"
    assert m.group(1) == flag, f"{name}: gated on {m.group(1)}, expected {flag}"

found = set(re.findall(r"\n    (\w+): Transition \{", qml))
assert found == set(gate), f"transitions changed: {sorted(found ^ set(gate))} -- gate them here too"
print("ok")
