#!/usr/bin/env python3
"""A notification group's header shows its whole app name when it fits.

TextMetrics.width is rounded to an int. "kitty" is 26.11px wide in the shipped font,
so a cap of `metrics.width` gave it 26 and it elided to "ki...", while "Beeper" (41.4)
rounded up to 42 and fit. The cap has to be the ceiling of `advanceWidth`, which is
what the Text itself measures.
"""
import re
from pathlib import Path

W = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/modules/common/widgets"
group = (W / "NotificationGroup.qml").read_text()

for m in re.finditer(r"Layout\.maximumWidth:\s*(.+)", group):
    expr = m.group(1)
    assert not re.search(r"[Mm]etrics\.width\b", expr), \
        f"NotificationGroup: `maximumWidth: {expr}` reads TextMetrics.width, which is rounded down as often as up"
assert re.search(r"Math\.ceil\(\s*appNameMetrics\.advanceWidth\s*\)", group), \
    "NotificationGroup: the app name cap is no longer ceil(advanceWidth)"

print("ok: the app name is capped at ceil(advanceWidth)")
