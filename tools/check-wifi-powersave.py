#!/usr/bin/env python3
"""The Wi-Fi dialog's power-saving switch reads the right interface and writes
the value it shows.

`scripts/network/wifi-powersave.sh` is a root helper the active session may run
without a password, and it keeps the choice in NetworkManager's config so it
outlives the shell. None of what can go wrong with it has a symptom:

- The switch has to grey out wherever a flip could not take -- no pkexec,
  NetworkManager stopped or not managing the adapter -- instead of snapping
  back on every click.
- `iw dev` lists P2P and AP interfaces too, and neither has a station power
  save. Asking the first `Interface` would report a hotspot's answer, or
  nothing, for the adapter that is actually connected.
- `802-11-wireless.powersave` is 2 for *disable* and 3 for *enable*. Swapping
  the two inverts the switch after the next reconnect and nowhere sooner, since
  `iw` has already set the live value.
- polkit only waives the password for the path in the policy's `exec.path`,
  and the shell only skips the reinstall prompt while its copy matches that
  path byte for byte. A path that drifts in one place asks for the password on
  every flip.
- A `Switch` toggles itself on click, which breaks `checked: <state>`. The
  switch would then show a flip whose prompt was cancelled, until the dialog
  is reopened.

    python3 tools/check-wifi-powersave.py
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHELL = ROOT / "dots/.config/quickshell/ii"
SCRIPT = SHELL / "scripts/network/wifi-powersave.sh"
SERVICE = SHELL / "services/Network.qml"
DIALOG = SHELL / "modules/ii/sidebarDashboard/wifiNetworks/WifiDialog.qml"

errors = []

# --- `get` asks the managed interface, whatever else is listed ---------------

IW_DEV = """phy#1
\tInterface ap0
\t\tifindex 5
\t\ttype AP
phy#0
\tUnnamed/non-netdev interface
\t\twdev 0x3
\t\ttype P2P-device
\tInterface wlan0
\t\tifindex 3
\t\tssid type
\t\ttype managed
"""

FAKE_IW = """#!/bin/sh
[ $# -eq 1 ] && { printf '%s' "$IW_DEV"; exit 0; }
echo "$*" >> "$IW_LOG"
printf 'Power save: %s\\n' "$IW_PS"
"""

# NM's answer for the device; exit 10 is what nmcli gives with NM stopped.
FAKE_NMCLI = """#!/bin/sh
[ -n "$NM_DOWN" ] && exit 10
echo "$NM_STATE"
"""


def get(listing, ps="on", pkexec=True, nm_state="100 (connected)", nm_down=False):
    """`get` on a sealed PATH: only these fakes and the tools it needs."""
    with tempfile.TemporaryDirectory() as tmp:
        for name, body in (("iw", FAKE_IW), ("nmcli", FAKE_NMCLI)) + ((("pkexec", "#!/bin/sh\n"),) if pkexec else ()):
            Path(tmp, name).write_text(body)
            Path(tmp, name).chmod(0o755)
        for tool in ("bash", "sh", "awk", "head"):
            Path(tmp, tool).symlink_to(shutil.which(tool))
        log = Path(tmp, "log")
        env = {"PATH": tmp, "IW_DEV": listing, "IW_PS": ps, "IW_LOG": str(log),
               "NM_STATE": nm_state, "NM_DOWN": "1" if nm_down else ""}
        out = subprocess.run([str(SCRIPT), "get"], env=env, capture_output=True, text=True).stdout
        return out.strip(), log.read_text() if log.exists() else ""


for ps in ("on", "off"):
    out, calls = get(IW_DEV, ps)
    if out != ps:
        errors.append(f"get printed {out!r} for power save {ps!r}")
    if calls.strip() != "dev wlan0 get power_save":
        errors.append(f"get asked {calls.strip()!r}, not the managed wlan0")

# Every one of these must print nothing, which greys the switch out.
for why, kwargs in (
    ("no managed interface", dict(listing=IW_DEV.replace("type managed", "type AP"))),
    ("no pkexec", dict(pkexec=False)),
    ("NetworkManager not running", dict(nm_down=True)),
    ("the adapter unmanaged by NM", dict(nm_state="10 (unmanaged)")),
):
    out, calls = get(**{"listing": IW_DEV, **kwargs})
    if out or calls:
        errors.append(f"get with {why} printed {out!r} after asking {calls.strip()!r}")

# --- on/off write the NM value that means that -------------------------------

src = SCRIPT.read_text()
if '"$([ "$1" = on ] && echo 3 || echo 2)"' not in src:
    errors.append("on/off no longer maps on -> 3 (enable), off -> 2 (disable)")

# --- one path everywhere ------------------------------------------------------

m = re.search(r"^BIN=(\S+)$", src, re.M)
bin_path = m.group(1) if m else None
if not bin_path or '<annotate key="org.freedesktop.policykit.exec.path">$BIN</annotate>' not in src:
    errors.append("the policy's exec.path is not the script's BIN")
service = SERVICE.read_text()
for path in re.findall(r"/usr/local/bin/[\w.-]+", service):
    if path != bin_path:
        errors.append(f"Network.qml runs {path}, the script installs {bin_path}")
if service.count(bin_path or "\0") != 2:
    errors.append("Network.qml should compare against and run the installed copy")

# --- the switch shows the state rather than keeping its own -----------------

switch = re.search(r"StyledSwitch\s*\{(.*?)\n\s*\}", DIALOG.read_text(), re.S)
if not switch or not re.search(r"checkable:\s*false", switch.group(1)):
    errors.append("WifiDialog's power-saving switch must be checkable: false")

if errors:
    print("wifi power save:")
    print("\n".join("  " + e for e in errors))
    sys.exit(1)

print("wifi power save: ok")
