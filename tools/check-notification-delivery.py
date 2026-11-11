#!/usr/bin/env python3
"""Observe actual Notify deliveries without interpreting notification contents.

An identical replacement changes no Quickshell properties. The delivery helper
therefore correlates typed D-Bus calls and successful replies, including clients
that reuse the same serial on different connections. New notifications, errors,
owner changes and unrelated traffic must never become replacement deliveries.

Use real Gio.DBusMessage and GLib.Variant objects with the production observer,
without connecting to a bus or playing sound. The notification service's private
D-Bus integration is covered separately by check-notifications.py.

Run: python3 tools/check-notification-delivery.py
"""
import importlib.util
from pathlib import Path

from gi.repository import Gio, GLib


II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
spec = importlib.util.spec_from_file_location("notification_delivery", II / "scripts/notifications/watch.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

OWNER = ":1.10"
CLIENT = ":1.20"
events = []
observer = helper.Replacements(OWNER, lambda **event: events.append(event))


def notify(replaces=42, *, sender=CLIENT, serial=1, destination=helper.NAME, with_body=True):
    message = Gio.DBusMessage.new_method_call(destination, helper.PATH, helper.NAME, "Notify")
    message.set_sender(sender)
    message.set_serial(serial)
    if with_body:
        message.set_body(GLib.Variant("(susssasa{sv}i)", (
            "Test app", replaces, "", "Unchanged summary", "Unchanged body",
            ["open", "Open"], {"resident": GLib.Variant("b", True)}, 1200,
        )))
    return message


def reply(call, returned=42, *, sender=OWNER, error=False):
    if error:
        message = call.new_method_error_literal("org.freedesktop.DBus.Error.Failed", "Rejected")
    else:
        message = call.new_method_reply()
        message.set_body(GLib.Variant("(u)", (returned,)))
    message.set_sender(sender)
    return message


def owner_changed(old, new, *, name=helper.NAME):
    message = Gio.DBusMessage.new_signal("/org/freedesktop/DBus", "org.freedesktop.DBus", "NameOwnerChanged")
    message.set_sender("org.freedesktop.DBus")
    message.set_body(GLib.Variant("(sss)", (name, old, new)))
    return message


def observe(message, incoming=True):
    return observer.observe(None, message, incoming, None)


first = notify()
assert observe(first) is None, "an intercepted call reached Gio's auto-reply dispatcher"
assert events == [], "the call was delivered before the server finished updating its object"
assert observe(reply(first)) is None
assert events == [{"replaced": 42}]
observe(reply(first))
assert events == [{"replaced": 42}], "a repeated reply delivered twice"

# An identical body still counts as a second delivery when its next call succeeds.
identical = notify(serial=2)
assert identical.get_body().equal(first.get_body())
observe(identical)
observe(reply(identical))
assert events == [{"replaced": 42}, {"replaced": 42}], "identical replacements were collapsed"

events.clear()
new = notify(0, serial=3)
observe(new)
assert not observer.pending, "a new notification was mistaken for a replacement"
observe(reply(new, 43))
unknown = notify(987654, serial=4)
observe(unknown)
observe(reply(unknown, 44))
failed = notify(serial=5)
observe(failed)
observe(reply(failed, error=True))
observe(reply(failed))
assert not events and not observer.pending, "new IDs or errors became replacement deliveries"

# Serial numbers belong to connections, not to the bus as a whole.
one = notify(45, serial=7)
two = notify(46, sender=":1.21", serial=7)
observe(one)
observe(two)
assert len(observer.pending) == 2
observe(reply(two, 46))
observe(reply(one, 45))
assert events == [{"replaced": 46}, {"replaced": 45}]

events.clear()
direct = notify(47, serial=8, destination=OWNER)
observe(direct)
observe(reply(direct, 47))
assert events == [{"replaced": 47}], "unique-name notification destinations were ignored"

events.clear()
old = notify(48, serial=9)
observe(old)
observe(owner_changed(OWNER, ":1.11", name="org.example.Unrelated"))
assert observer.owner == OWNER and len(observer.pending) == 1
observe(owner_changed(OWNER, ""))
assert observer.owner == "" and not observer.pending
observe(reply(old, 48))
observe(owner_changed("", ":1.11"))
assert observer.owner == ":1.11"
observe(reply(old, 48, sender=":1.11"))
assert not events, "a previous owner's pending call survived an owner change"
reused = notify(1, serial=9, destination=":1.11")
observe(reused)
observe(reply(reused, 1, sender=":1.11"))
assert events == [{"replaced": 1}], "a fresh owner could not reuse an old notification ID"

observer = helper.Replacements(OWNER, lambda **event: events.append(event))
events.clear()
for malformed_body in (None, GLib.Variant("(s)", ("not a Notify request",))):
    malformed = notify(serial=10, with_body=False)
    if malformed_body is not None:
        malformed.set_body(malformed_body)
    assert observe(malformed) is None
    assert not observer.pending
for change in (
    lambda message: message.set_member("GetCapabilities"),
    lambda message: message.set_interface("org.example.Other"),
    lambda message: message.set_path("/org/example/Other"),
    lambda message: message.set_destination(":1.99"),
):
    unrelated = notify(serial=11)
    change(unrelated)
    assert observe(unrelated) is None, "an unrelated intercepted method call was auto-dispatched"
    assert not observer.pending

outgoing = notify(serial=12)
assert observe(outgoing, False) is outgoing and not observer.pending
setup = Gio.DBusMessage.new_method_call("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                      "org.freedesktop.DBus.Monitoring", "BecomeMonitor")
setup.set_sender(":1.30")
setup.set_serial(1)
setup_reply = setup.new_method_reply()
setup_reply.set_sender("org.freedesktop.DBus")
assert observe(setup_reply) is setup_reply, "BecomeMonitor's reply never reached call_sync"

for body in (None, GLib.Variant("(s)", ("wrong reply type",))):
    call = notify(serial=13)
    observe(call)
    malformed_reply = call.new_method_reply()
    malformed_reply.set_sender(OWNER)
    if body is not None:
        malformed_reply.set_body(body)
    observe(malformed_reply)
assert not events and not observer.pending
foreign = notify(serial=14)
observe(foreign)
observe(reply(foreign, sender=":1.99"))
assert not events, "a foreign connection's reply was trusted as the notification server"

observer = helper.Replacements(OWNER, lambda **event: events.append(event))
for serial in range(1, 1101):
    observe(notify(serial=serial))
assert 0 < len(observer.pending) <= 1024, "unanswered calls grew without bound"
assert (CLIENT, 1) not in observer.pending, "the oldest unanswered call was not evicted"
assert (CLIENT, 1100) in observer.pending, "bounding the queue discarded its newest call"
observe(reply(notify(serial=1)))
assert not events, "an evicted call still produced a delivery"
observe(reply(notify(serial=1100)))
assert events == [{"replaced": 42}]

print("ok: typed notification deliveries correlate once, survive identical bodies and owner changes, and stay bounded")
