#!/usr/bin/env python3
"""ConfigSwitch flips itself with toggle(), never by assigning `checked`.

A JS assignment to `checked` drops the caller's `checked:` binding; a C++ write such as
AbstractButton.toggle() keeps it (measured with qml6 on Qt 6.11). Without the binding a
row stops following its source. On the Background page every Desktop / Lock screen
section is one set of rows whose `checked: section.opt.enable` retargets with the tab,
so after one click the lock tab showed the desktop's state, and the next click wrote
the wrong value into the lock's config - shape, depth, weather, glass and blur alike.
The hotspot, Night Light and battery-limit rows had each dodged it by not using
ConfigSwitch at all.

Run: python3 tools/check-config-switch-binding.py
"""
import re
from pathlib import Path

W = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/modules/common/widgets"
src = re.sub(r"//[^\n]*", "", (W / "ConfigSwitch.qml").read_text())

assert not re.search(r"\bchecked\s*=(?!=)", src), \
    "ConfigSwitch: assigning `checked` drops the caller's binding; flip it with root.toggle()"
assert re.search(r"onClicked:\s*if\s*\(\s*toggles\s*\)\s*root\.toggle\(\)", src), \
    "ConfigSwitch: a click must flip the switch through root.toggle()"

print("ok: ConfigSwitch keeps its caller's checked binding")
