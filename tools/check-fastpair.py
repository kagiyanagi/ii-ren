#!/usr/bin/env python3
"""A Fast Pair snooze covers the device, and a mute outlives the shell.

`services/FastPair.qml` decides three things that only a pair of earbuds in
pairing mode can demonstrate, which is why they went wrong quietly:

- **One device is not one address.** During discovery BlueZ hands back a
  separate Device1 for the classic inquiry result and for the LE scan result,
  with different addresses and the same name, and an unbonded LE address is
  rotated by the peripheral every few minutes. Suppressing the one address the
  card was showing left the sibling offerable on the next dump two seconds
  later, so a snooze looked like it did nothing at all - intermittently, which
  is the worst way for it to look. Keys are the address *and* the name now.

- **Discovery is shared.** Quickshell has one D-Bus connection for the whole
  shell, so the Bluetooth dialog or blueman can hold the adapter in discovery
  while an attempt of ours is running. A dump landing then re-entered
  pickCandidate, which overwrote the candidate and cleared `busy` - orphaning
  the pairing and leaking the bluetoothctl agent. Nothing about it is visible.

- **A mute is a wall-clock promise.** It used to be a plain property, so a QML
  reload or `iiren run` voided "not for six hours". Persisting it means it has
  to expire on its own and be escapable from the settings app, or the promise
  becomes permanent.

The popup timeout is checked too: it must hold while the card is being used,
because the countdown running through the options menu snoozes the device for
the default five minutes just as the user reaches for "1h".

    python3 tools/check-fastpair.py
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHELL = ROOT / "dots/.config/quickshell/ii"
SERVICE = (SHELL / "services/FastPair.qml").read_text()
POPUP = (SHELL / "modules/ii/fastPair/FastPairPopup.qml").read_text()
CONFIG = (SHELL / "modules/common/Config.qml").read_text()
SETTINGS = (SHELL / "modules/settings/ServicesConfig.qml").read_text()

NOW = 1_700_000_000_000


# -- the identity predicates, lifted out of identityKeys/suppressed/ignored ---


def identity_keys(device):
    return [k for k in (device.get("address"), device.get("name")) if k]


def suppressed(device, until_map, now=NOW):
    return any(until_map.get(k, 0) > now for k in identity_keys(device))


def ignored(device, ignored_list):
    return any(k in ignored_list for k in identity_keys(device))


def snooze(device, ms, until_map, now=NOW):
    out = dict(until_map)
    for key in identity_keys(device):
        out[key] = now + ms
    return out


# One pair of earbuds, as BlueZ actually presents them while scanning.
CLASSIC = {"address": "AC:BC:32:11:22:33", "name": "Pixel Buds Pro"}
LE = {"address": "5F:1A:9C:44:55:66", "name": "Pixel Buds Pro"}
ROTATED = {"address": "6B:22:EE:77:88:99", "name": "Pixel Buds Pro"}
OTHER = {"address": "00:11:22:33:44:55", "name": "Someone's Speaker"}


def check_snooze_covers_the_device():
    after = snooze(CLASSIC, 3_600_000, {})
    for sibling, what in ((CLASSIC, "the address it was offered under"), (LE, "its LE sibling"), (ROTATED, "the same device after an address rotation")):
        assert suppressed(sibling, after), f"a snooze does not cover {what}"
    assert not suppressed(OTHER, after), "a snooze covers an unrelated device"
    assert not suppressed(CLASSIC, after, now=NOW + 3_600_001), "a snooze never expires"
    print("ok  snooze: covers both BlueZ objects and survives a rotation, expires on time")


def check_ignore_covers_the_device():
    stored = [k for k in identity_keys(CLASSIC) if k == CLASSIC["name"]]
    assert stored == ["Pixel Buds Pro"], "ignoreCandidate stores something other than the name"
    assert ignored(ROTATED, stored), "a permanent ignore does not survive an address rotation"
    assert not ignored(OTHER, stored), "a permanent ignore catches an unrelated device"
    # Entries written before the change are addresses, and must keep working.
    assert ignored(CLASSIC, ["AC:BC:32:11:22:33"]), "a legacy address entry stopped matching"
    print("ok  ignore: matches by name, legacy address entries still match")


def check_source_uses_the_predicates():
    for fn in ("function identityKeys(", "function suppressed(", "function ignored("):
        assert fn in SERVICE, f"FastPair.qml no longer defines {fn}...)"
    filter_body = SERVICE.split("function pickCandidate()")[1].split("function connectCandidate")[0]
    assert "root.suppressed(device)" in filter_body, "pickCandidate stopped asking suppressed()"
    assert "root.ignored(device)" in filter_body, "pickCandidate stopped asking ignored()"
    assert "suppressedUntil[device.address]" not in filter_body, "pickCandidate is back to one address per device"
    guard = re.search(r"if \(root\.popupShown([^)]*)\)\s*\n\s*return;", filter_body)
    assert guard, "pickCandidate lost its early return"
    for flag, why in (("root.busy", "a dump landing mid-attempt orphans the pairing"), ("root.muted", "a mute is ignored when something else holds discovery")):
        assert flag in guard.group(1), f"pickCandidate does not refuse on {flag}: {why}"
    print("ok  pick: refuses while busy or muted, and asks the identity predicates")


def check_mute_is_a_promise_about_the_clock():
    assert "property real mutedUntil: 0" in CONFIG, "Config has no fastPair.mutedUntil, so a mute dies with the shell"
    assert "readonly property real mutedUntil: root.options.mutedUntil" in SERVICE, "the service keeps its own mutedUntil again"
    assert "root.options.mutedUntil = Date.now() + ms" in SERVICE, "muteAll no longer writes through Config"
    scan = re.search(r"readonly property bool shouldScan:(.*)", SERVICE).group(1)
    assert "!root.muted" in scan, "a mute leaves the adapter discovering for its whole duration"
    expiry = re.search(r"Timer \{\s*running: root\.muted(.*?)\n    \}", SERVICE, re.S)
    assert expiry, "nothing expires the mute, so a persisted one is permanent"
    assert "root.unmute()" in expiry.group(1), "the mute expiry does not clear it"
    assert "repeat: true" in expiry.group(1), "the mute expiry fires once, so a suspend outlives it"
    assert "mutedUntil = 0" in SETTINGS, "settings offers no way out of a six-hour mute"
    print("ok  mute: persisted, stops the radio, expires on the wall clock, escapable")


def check_the_timeout_waits_for_the_user():
    running = re.search(r"id: autoDismiss\s*\n\s*running:(.*)", SERVICE).group(1)
    for flag, why in (
        ("root.popupShown", "it counts down with no card up"),
        ("!root.busy", "it snoozes a device that is connecting"),
        ("!root.interacting", "it snoozes the card out from under the options menu"),
        ("root.options.popupTimeout > 0", "0 no longer means never"),
    ):
        assert flag in running, f"autoDismiss does not check {flag}: {why}"
    assert "autoDismiss.restart()" not in SERVICE, "autoDismiss is restarted by hand again, so one path will forget"
    assert re.search(r'property: "interacting"', POPUP), "the card never reports that it is being used"
    assert "HoverHandler" in POPUP, "the card has no hover to hold the timeout with"
    print("ok  timeout: declarative, and holds while the card is hovered or open")


if __name__ == "__main__":
    check_snooze_covers_the_device()
    check_ignore_covers_the_device()
    check_source_uses_the_predicates()
    check_mute_is_a_promise_about_the_clock()
    check_the_timeout_waits_for_the_user()
    print("\nall ok")
