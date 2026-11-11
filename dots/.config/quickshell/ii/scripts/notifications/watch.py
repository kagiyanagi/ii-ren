#!/usr/bin/env python3
"""Report successful Notify replacements, including identical payloads.

Quickshell 0.3.2 has no delivery signal for replacements. A dedicated typed
D-Bus monitor observes their replies after Quickshell has updated its objects.
Only readiness and notification IDs leave this process, never message contents.
PyGObject is already used by the shell's KDE Connect and fingerprint helpers.
"""
import json
import sys
from collections import OrderedDict

from gi.repository import Gio, GLib

NAME = "org.freedesktop.Notifications"
PATH = "/org/freedesktop/Notifications"
RULES = [
    f"type='method_call',interface='{NAME}',member='Notify',path='{PATH}'",
    f"type='method_return',sender='{NAME}'",
    f"type='error',sender='{NAME}'",
    "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',"
    f"member='NameOwnerChanged',arg0='{NAME}'",
]


def emit(**event):
    print(json.dumps(event), flush=True)


class Replacements:
    def __init__(self, owner="", report=emit):
        self.owner = owner
        self.pending = OrderedDict()
        self.report = report

    def observe(self, connection, message, incoming, data):
        if not incoming:
            return message
        kind = message.get_message_type()
        body = message.get_body()
        if (kind == Gio.DBusMessageType.SIGNAL
                and message.get_sender() == "org.freedesktop.DBus"
                and message.get_member() == "NameOwnerChanged"
                and body is not None and body.get_type_string() == "(sss)"):
            name, _, owner = body.unpack()
            if name == NAME:
                self.owner = owner
                self.pending.clear()
        elif kind == Gio.DBusMessageType.METHOD_CALL:
            if (message.get_interface() == NAME and message.get_member() == "Notify"
                    and message.get_path() == PATH
                    and message.get_destination() in (NAME, self.owner)
                    and body is not None and body.get_type_string() == "(susssasa{sv}i)"):
                replaces = body.get_child_value(1).get_uint32()
                if replaces:
                    self.pending[(message.get_sender(), message.get_serial())] = replaces
                    # Bound unanswered calls, including a client sending malformed
                    # traffic indefinitely. Normal Notify calls reply immediately.
                    if len(self.pending) > 1024:
                        self.pending.popitem(last=False)
            # Dispatching an intercepted call would make Gio auto-reply with
            # UnknownMethod. A monitor must never answer another connection's call.
            return None
        elif kind in (Gio.DBusMessageType.METHOD_RETURN, Gio.DBusMessageType.ERROR):
            key = (message.get_destination(), message.get_reply_serial())
            replaces = self.pending.pop(key, None)
            if replaces is not None:
                if (kind == Gio.DBusMessageType.METHOD_RETURN
                        and message.get_sender() == self.owner
                        and body is not None and body.get_type_string() == "(u)"
                        and body.get_child_value(0).get_uint32() == replaces):
                    self.report(replaced=replaces)
                return None
        # The connection's own BecomeMonitor reply must reach call_sync().
        return message


def main():
    control = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    owner = ""
    try:
        owner = control.call_sync(
            "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
            "GetNameOwner", GLib.Variant("(s)", (NAME,)), GLib.VariantType.new("(s)"),
            Gio.DBusCallFlags.NONE, 5000, None,
        ).unpack()[0]
    except GLib.Error:
        pass  # The shell starts its notification server after our ready event.
    address = Gio.dbus_address_get_for_bus_sync(Gio.BusType.SESSION, None)
    connection = Gio.DBusConnection.new_for_address_sync(
        address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
        | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None,
    )
    observer = Replacements(owner)
    connection.add_filter(observer.observe, None)
    connection.call_sync(
        "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus.Monitoring",
        "BecomeMonitor", GLib.Variant("(asu)", (RULES, 0)), None,
        Gio.DBusCallFlags.NONE, 5000, None,
    )
    loop = GLib.MainLoop()
    connection.connect("closed", lambda *_: loop.quit())
    emit(ready=True)
    loop.run()
    return 1  # KeepAliveProcess reconnects after the session bus closes.


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except GLib.Error as error:
        print(f"Notification delivery observer: {error}", file=sys.stderr)
        raise SystemExit(1)
