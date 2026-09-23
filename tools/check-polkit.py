#!/usr/bin/env python3
"""The polkit dialog leaves visibly, and says why a password did not work.

None of this has a symptom a still frame shows.

* The **exit**. The `AuthFlow` is deleted on the frame it completes, so a `Loader`
  bound to `PolkitService.active` unmapped the window on that frame and no success
  or cancel ever animated. The window is now latched: set on the edge, released by
  the content once `WindowDialog` has collapsed. `active` must not read the flag
  even as one half of an `||` -- the binding and the handler race on one change
  signal (measured in `check-osk.py`). Measured here: unmapped ~100ms after Esc,
  which is the dialog's own collapse, against the same frame before.
* **What the dialog says survives the flow.** Bound to `PolkitService`, the message
  emptied on the exit's first frame and pulled the field up a line.
* **A wrong password is said.** polkit reports it only as `authenticationFailed` and
  silently starts a new session, so the field just cleared. The status line takes
  the lock screen's order: PAM first -- pam_faillock refuses a locked account before
  pam_unix sees the password, and its tally is shared with the lock screen -- then
  the failure, then Caps Lock.
* **The field is live only while PAM is asking.** `interactionAvailable` was written
  by hand on request start and on failure, both before the session asks for
  anything; it is `flow.isResponseRequired` now, and nothing may assign it.
* **`WindowDialog` follows its content while shown.** Its default height read the
  card's own height, which `onShowChanged` then overwrote with a snapshot, so the
  status line -- and `KeybindEditor`'s conflict row -- was laid out past the card.

Run: python3 tools/check-polkit.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
II = ROOT / "dots/.config/quickshell/ii"

window = (II / "modules/common/widgets/FullscreenPolkitWindow.qml").read_text()
dialog = (II / "modules/common/widgets/WindowDialog.qml").read_text()
host = (II / "modules/ii/polkit/Polkit.qml").read_text()
content = (II / "modules/ii/polkit/PolkitContent.qml").read_text()
service = (II / "services/PolkitService.qml").read_text()

failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)


def block(src, head):
    """The brace-balanced body that follows the first match of `head`."""
    m = re.search(head, src)
    if not m:
        return None
    i = src.index("{", m.end() - 1)
    depth = 0
    for j in range(i, len(src)):
        depth += {"{": 1, "}": -1}.get(src[j], 0)
        if depth == 0:
            return src[i + 1:j]
    return None


def code(src):
    return "\n".join(line.split("//")[0] for line in src.splitlines())


# ── the latch ────────────────────────────────────────────────────────────────

active = re.search(r"^\s*active:\s*(.+)$", code(window), re.M)
check(active and active.group(1).strip() == "root.rendered",
      f"FullscreenPolkitWindow's Loader.active must be the latch alone, got "
      f"{active.group(1).strip() if active else None!r}")
check(not re.search(r"property bool rendered:\s*PolkitService", code(window)),
      "`rendered` must not be bound to PolkitService -- it is assigned on the edge")
edge = block(code(window), r"function onActiveChanged\(\)")
check(edge is not None and "holdForExit" in edge,
      "onActiveChanged must leave the latch set for content that holds its exit")
check(re.search(r"holdForExit:\s*true", code(host)) is not None,
      "Polkit.qml must hold the window for its exit")
check(re.search(r"onClosed:\s*root\.release\(\)", code(host)) is not None,
      "Polkit.qml must release the window when the dialog has closed")
closed = block(code(content), r"onVisibleChanged:")
check(closed is not None and "!visible" in closed and "PolkitService.active" in closed
      and "root.closed()" in closed,
      "the content must report `closed` only once the dialog is invisible and no "
      "flow is active -- a queued request re-shows the same dialog")

# ── what the dialog says ─────────────────────────────────────────────────────

para = block(code(content), r"WindowDialogParagraph\s*\{")
check(para is not None and re.search(r"text:\s*root\.message\b", para),
      "the message must be the content's copy, not bound to the flow")
cap = block(code(content), r"function capture\(\)")
check(cap is not None and re.search(r"if \(!flow\)\s*return", cap),
      "capture() must keep the last words when the flow is gone")

status = block(code(content), r"readonly property string status:")
order = re.findall(r"if \(([^)]*)\)", status or "")
check(order == ["root.pamMessage.length > 0", "root.failed", "HyprlandXkb.capsLock"],
      f"status must be PAM, then the failure, then Caps Lock (the lock screen's "
      f"order); got {order}")
failed = block(code(content), r"function onAuthenticationFailed\(\)")
check(failed is not None and "root.failed = true" in failed,
      "authenticationFailed is the only report of a wrong password -- it must set it")
check(re.search(r"function submit\(\)\s*\{\s*root\.failed = false", code(content)),
      "a new attempt must clear the last failure")

# ── the field ────────────────────────────────────────────────────────────────

check(re.search(r"readonly property bool interactionAvailable:\s*root\.flow\?\."
                r"isResponseRequired", code(service)),
      "interactionAvailable must be derived from flow.isResponseRequired")
check(not re.search(r"interactionAvailable\s*=[^=]", code(service) + code(content)),
      "nothing may assign interactionAvailable")
check("Keys.onPressed" not in code(content).split("WindowDialog {", 1)[0],
      "Esc belongs to WindowDialog's own handler; the content must not add a second")

# ── WindowDialog follows its content ─────────────────────────────────────────

bh = re.search(r"property real backgroundHeight:\s*(.+)$", code(dialog), re.M)
check(bh and "dialogBackground" not in bh.group(1),
      "backgroundHeight's default must come from the content, not the card it sizes "
      f"(got {bh.group(1).strip() if bh else None!r})")
check(re.search(r"implicitHeight = show \? Qt\.binding\(", code(dialog)),
      "onShowChanged must bind the shown height, not snapshot it")

if failures:
    print("check-polkit: FAIL")
    for f in failures:
        print("  -", f)
    sys.exit(1)
print("check-polkit: ok")
