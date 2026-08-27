#!/usr/bin/env python3
"""KDE Connect -> JSON snapshot stream for the Continuity sidebar page.

Prints one JSON object per line whenever anything about the paired devices
changes. Subscribes to *every* signal from org.kde.kdeconnect rather than
naming them: the signal set is version-dependent and a snapshot is a handful of
cheap property reads, so a name filter would be more code guarding less.
"""

import json
import os
import re
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS = "org.kde.kdeconnect"
DAEMON_PATH = "/modules/kdeconnect"
DEV_PATH = "/modules/kdeconnect/devices/"
IF = "org.kde.kdeconnect."

# Long enough to coalesce the burst a phone sends when it reconnects, short
# enough that a notification still feels instant.
DEBOUNCE_MS = 180
# Signals cover everything in practice; this is only here so a missed one
# cannot leave the panel stale forever.
RESYNC_MS = 60_000

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
_notification_iface = None


def call(path, iface, method, args=None, signature="()"):
    try:
        reply = bus.call_sync(
            BUS, path, iface, method,
            GLib.Variant(signature, args) if args is not None else None,
            None, Gio.DBusCallFlags.NONE, 3000, None)
        return reply.unpack()
    except GLib.Error:
        return None


def props(path, iface):
    got = call(path, "org.freedesktop.DBus.Properties", "GetAll", (iface,), "(s)")
    return got[0] if got else {}


def notification_iface(path):
    """KDE has renamed this interface before; ask the object once and cache."""
    global _notification_iface
    if _notification_iface:
        return _notification_iface
    xml = call(path, "org.freedesktop.DBus.Introspectable", "Introspect")
    if xml:
        for name in re.findall(r'interface name="([^"]+)"', xml[0]):
            if name.startswith("org.kde.kdeconnect"):
                _notification_iface = name
                break
    return _notification_iface or IF + "device.notifications.notification"


def notifications_of(device_id):
    base = DEV_PATH + device_id + "/notifications"
    got = call(base, IF + "device.notifications", "activeNotifications")
    out = []
    for nid in (got[0] if got else []):
        p = props(base + "/" + nid, notification_iface(base + "/" + nid))
        if not p:
            continue
        out.append({
            "id": nid,
            "deviceId": device_id,
            "appName": p.get("appName", ""),
            "title": p.get("title", ""),
            "text": p.get("text", ""),
            "ticker": p.get("ticker", ""),
            "iconPath": p.get("iconPath", ""),
            "dismissable": bool(p.get("dismissable", False)),
            "replyId": p.get("replyId", ""),
            "silent": bool(p.get("silent", False)),
            "actions": list(p.get("actions", []) or []),
        })
    return out


def snapshot():
    got = call(DAEMON_PATH, IF + "daemon", "devices")
    if got is None:
        return {"available": False, "devices": [], "notifications": []}

    devices, notifications = [], []
    for did in got[0]:
        path = DEV_PATH + did
        d = props(path, IF + "device")
        if not d:
            continue
        plugins = list(d.get("supportedPlugins", []) or [])
        battery = props(path + "/battery", IF + "device.battery")
        signal = props(path + "/connectivity_report", IF + "device.connectivity_report")
        reachable = bool(d.get("isReachable", False))
        devices.append({
            "id": did,
            "name": d.get("name", did),
            "type": d.get("type", "device"),
            "paired": bool(d.get("isPaired", False)),
            "reachable": reachable,
            "addresses": list(d.get("reachableAddresses", []) or []),
            "plugins": plugins,
            "hasBattery": bool(battery.get("hasBattery", False)),
            "charge": int(battery.get("charge", -1)),
            "charging": bool(battery.get("isCharging", False)),
            "signalStrength": int(signal.get("cellularNetworkStrength", -1)),
            "signalType": signal.get("cellularNetworkType", ""),
            # Aliases the ported desktop widgets read under these names.
            "batteryCharge": int(battery.get("charge", -1)),
            "isCharging": bool(battery.get("isCharging", False)),
            "isReachable": reachable,
        })
        if reachable and "kdeconnect_notifications" in plugins:
            notifications += notifications_of(did)

    return {"available": True, "devices": devices, "notifications": notifications}


_last = None
_pending = False


def emit():
    """Only prints when something actually differs - a phone on the network
    chatters, and redrawing the panel on every heartbeat is visible."""
    global _last, _pending
    _pending = False
    snap = snapshot()
    if snap != _last:
        _last = snap
        sys.stdout.write(json.dumps(snap) + "\n")
        sys.stdout.flush()
    return GLib.SOURCE_REMOVE


def schedule(*_args):
    global _pending
    if not _pending:
        _pending = True
        GLib.timeout_add(DEBOUNCE_MS, emit)


bus.signal_subscribe(BUS, None, None, None, None, Gio.DBusSignalFlags.NONE,
                     lambda *a: schedule(), None)
Gio.bus_watch_name(Gio.BusType.SESSION, BUS, Gio.BusNameWatcherFlags.NONE,
                   lambda *a: schedule(), lambda *a: schedule())
GLib.timeout_add(RESYNC_MS, lambda: (schedule(), True)[1])

if "--once" in sys.argv:
    # Debug/self-check: one snapshot, no loop. Every key here is read by
    # services/KdeConnectService.qml or by a ported desktop widget.
    snap = snapshot()
    assert set(snap) == {"available", "devices", "notifications"}, snap.keys()
    for d in snap["devices"]:
        missing = {"id", "name", "type", "paired", "reachable", "hasBattery", "charge",
                   "charging", "batteryCharge", "isCharging", "isReachable",
                   "plugins", "signalStrength", "signalType"} - set(d)
        assert not missing, missing
    for n in snap["notifications"]:
        missing = {"id", "deviceId", "appName", "title", "text", "dismissable",
                   "replyId", "actions"} - set(n)
        assert not missing, missing
    print(json.dumps(snap, indent=2))
    sys.exit(0)

# Quickshell doesn't reap us when it's killall'd; without this, every shell
# restart leaks another copy of this monitor.
_parent = os.getppid()
GLib.timeout_add(2000, lambda: os.getppid() == _parent or os._exit(0))

emit()
GLib.MainLoop().run()
