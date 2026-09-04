#!/usr/bin/env python3
"""fprintd <-> JSON bridge for the fingerprint settings page.

Reads one JSON command per line on stdin, prints one JSON event per line on
stdout. It has to be a long-lived process rather than a call per operation:
fprintd ties Claim() to the D-Bus connection that made it, so enrolling means
Claim, EnrollStart, a run of EnrollStatus signals and EnrollStop all arriving
over the *same* connection. A `busctl call` per step would be released the
moment each one exited.

Commands:
    {"cmd": "refresh"}
    {"cmd": "enroll",  "finger": "right-index-finger"}
    {"cmd": "verify",  "finger": "right-index-finger"}
    {"cmd": "cancel"}
    {"cmd": "delete",  "finger": "right-index-finger"}
    {"cmd": "delete-all"}

Events (see `type`): device, enrolled, enroll, verify, error.
"""

import getpass
import json
import os
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS = "net.reactivated.Fprint"
MANAGER_PATH = "/net/reactivated/Fprint/Manager"
MANAGER_IF = "net.reactivated.Fprint.Manager"
DEVICE_IF = "net.reactivated.Fprint.Device"
PROPS_IF = "org.freedesktop.DBus.Properties"

# Claim() can sit behind a polkit prompt, and enroll/verify only end when a
# finger touches the reader, so neither can use the default 25s timeout.
CALL_TIMEOUT_MS = 120_000
QUICK_TIMEOUT_MS = 5_000

# fprintd reports scan feedback through the same signal as real progress. Only
# the two terminal codes end an operation; the rest are "try that again".
ENROLL_RETRY = {
    "enroll-retry-scan": "Didn't catch that — try again",
    "enroll-swipe-too-short": "Swipe was too short",
    "enroll-finger-not-centered": "Center your finger on the reader",
    "enroll-remove-and-retry": "Lift your finger and touch again",
    "enroll-duplicate": "That finger is already enrolled as another one",
}
ENROLL_FATAL = {
    "enroll-failed": "Enrollment failed",
    "enroll-data-full": "The reader has no room left for another fingerprint",
    "enroll-disconnected": "The reader was disconnected",
    "enroll-unknown-error": "The reader reported an unknown error",
}
VERIFY_RETRY = {
    "verify-retry-scan": "Didn't catch that — try again",
    "verify-swipe-too-short": "Swipe was too short",
    "verify-finger-not-centered": "Center your finger on the reader",
    "verify-remove-and-retry": "Lift your finger and touch again",
}
VERIFY_FATAL = {
    "verify-no-match": "That finger doesn't match",
    "verify-disconnected": "The reader was disconnected",
    "verify-unknown-error": "The reader reported an unknown error",
}


def emit(**event):
    sys.stdout.write(json.dumps(event) + "\n")
    sys.stdout.flush()


def username():
    # getpass falls back to LOGNAME/USER/LNAME/USERNAME, any of which can be
    # wrong or missing under a display manager. The uid never is.
    try:
        import pwd
        return pwd.getpwuid(os.getuid()).pw_name
    except Exception:
        return getpass.getuser()


class Bridge:
    def __init__(self):
        self.user = username()
        self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        self.device = None
        self.claimed = False
        # "" | "enroll" | "verify"
        self.operation = ""
        self.finger = ""
        self.stage = 0
        self.num_stages = 5
        self.subscriptions = []
        self.state_subscription = None
        self.reader_state = {"finger-needed": False, "finger-present": False}

    # ── D-Bus plumbing ────────────────────────────────────────────────────

    def call(self, path, iface, method, args=None, signature="()",
             timeout=QUICK_TIMEOUT_MS):
        """Synchronous call. Returns the unpacked reply, or None on failure."""
        try:
            reply = self.bus.call_sync(
                BUS, path, iface, method,
                GLib.Variant(signature, args) if args is not None else None,
                None, Gio.DBusCallFlags.NONE, timeout, None)
            return reply.unpack()
        except GLib.Error as e:
            self.last_error = e.message
            return None

    def call_async(self, method, args, signature, on_done, timeout=CALL_TIMEOUT_MS):
        """Async call on the current device, so stdin stays live for cancel."""
        def finished(bus, result):
            try:
                on_done(bus.call_finish(result).unpack(), None)
            except GLib.Error as e:
                on_done(None, e.message)

        self.bus.call(
            BUS, self.device, DEVICE_IF, method,
            GLib.Variant(signature, args) if args is not None else None,
            None, Gio.DBusCallFlags.NONE, timeout, None, finished)

    def subscribe(self, signal, handler):
        self.subscriptions.append(self.bus.signal_subscribe(
            BUS, DEVICE_IF, signal, self.device, None,
            Gio.DBusSignalFlags.NONE,
            lambda c, s, p, i, sig, params: handler(*params.unpack())))

    def unsubscribe_all(self):
        for sub in self.subscriptions:
            self.bus.signal_unsubscribe(sub)
        self.subscriptions = []

    # ── Device discovery ──────────────────────────────────────────────────

    def find_device(self):
        """Pick a reader. fprintd is D-Bus activated, so this also starts it.

        Ask for the default rather than taking GetDevices()[0]: a Dell
        ControlVault publishes two Device objects for the one sensor, only one
        of which initialises, and GetDevices does not return them in a
        dependable order. GetDefaultDevice is what fprintd's own CLI tools use.
        """
        default = self.call(MANAGER_PATH, MANAGER_IF, "GetDefaultDevice")
        if default and default[0]:
            self.device = default[0]
            return self.device

        devices = self.call(MANAGER_PATH, MANAGER_IF, "GetDevices")
        self.device = devices[0][0] if devices and devices[0] else None
        return self.device

    def watch_reader_state(self):
        """Follow finger-needed / finger-present for the whole process life.

        These are plain properties, so reading them needs no claim — which is
        the point: during a lock screen it is pam_fprintd that owns the device,
        and this is the only way to know the sensor is being touched without
        fighting it for the claim. Drivers are not obliged to drive either
        property, so treat both as best-effort.
        """
        if self.state_subscription is not None:
            return

        def changed(_iface, changed_props, _invalidated):
            wanted = ("finger-needed", "finger-present")
            if not any(k in changed_props for k in wanted):
                return
            for key in wanted:
                if key in changed_props:
                    self.reader_state[key] = bool(changed_props[key])
            emit(type="reader",
                 fingerNeeded=self.reader_state["finger-needed"],
                 fingerPresent=self.reader_state["finger-present"])

        self.state_subscription = self.bus.signal_subscribe(
            BUS, PROPS_IF, "PropertiesChanged", self.device, None,
            Gio.DBusSignalFlags.NONE,
            lambda c, s, p, i, sig, params: changed(*params.unpack()))

    def report_device(self):
        if not self.find_device():
            emit(type="device", available=False, name="", numEnrollStages=5,
                 scanType="press")
            return False

        props = self.call(self.device, PROPS_IF, "GetAll", (DEVICE_IF,), "(s)")
        props = props[0] if props else {}
        self.num_stages = int(props.get("num-enroll-stages", 5) or 5)
        for key in ("finger-needed", "finger-present"):
            self.reader_state[key] = bool(props.get(key, False))
        emit(type="device",
             available=True,
             name=props.get("name", ""),
             numEnrollStages=self.num_stages,
             scanType=props.get("scan-type", "press"))
        emit(type="reader",
             fingerNeeded=self.reader_state["finger-needed"],
             fingerPresent=self.reader_state["finger-present"])
        self.watch_reader_state()
        return True

    def report_enrolled(self):
        if not self.device:
            emit(type="enrolled", fingers=[])
            return
        fingers = self.call(self.device, DEVICE_IF, "ListEnrolledFingers",
                            (self.user,), "(s)")
        # A user with nothing enrolled is an error reply, not an empty list.
        emit(type="enrolled", fingers=list(fingers[0]) if fingers else [])

    # ── Claim / release ───────────────────────────────────────────────────

    def claim(self, on_done):
        if self.claimed:
            on_done(None, None)
            return
        def finished(_result, error):
            self.claimed = error is None
            on_done(None, error)
        self.call_async("Claim", (self.user,), "(s)", finished)

    def release(self):
        if not self.claimed:
            return
        self.claimed = False
        self.call(self.device, DEVICE_IF, "Release", timeout=QUICK_TIMEOUT_MS)

    def finish_operation(self):
        """Tear an operation down without touching what was already emitted."""
        if self.operation == "enroll":
            self.call(self.device, DEVICE_IF, "EnrollStop")
        elif self.operation == "verify":
            self.call(self.device, DEVICE_IF, "VerifyStop")
        self.unsubscribe_all()
        self.release()
        self.operation = ""

    # ── Enroll ────────────────────────────────────────────────────────────

    def enroll(self, finger):
        if self.operation:
            self.finish_operation()
        if not self.device and not self.find_device():
            emit(type="enroll", phase="failed", stage=0,
                 message="No fingerprint reader available")
            return

        self.operation = "enroll"
        self.finger = finger
        self.stage = 0
        emit(type="enroll", phase="authorizing", stage=0,
             message="Waiting for authorization…")

        def claimed(_result, error):
            if error is not None:
                self.operation = ""
                emit(type="enroll", phase="failed", stage=0, message=error)
                return
            self.subscribe("EnrollStatus", self.on_enroll_status)

            def started(_result, start_error):
                if start_error is not None:
                    self.finish_operation()
                    emit(type="enroll", phase="failed", stage=0,
                         message=start_error)
                    return
                emit(type="enroll", phase="scanning", stage=0,
                     message="Touch the reader")

            self.call_async("EnrollStart", (finger,), "(s)", started)

        self.claim(claimed)

    def on_enroll_status(self, result, done):
        if self.operation != "enroll":
            return

        if result == "enroll-stage-passed":
            self.stage = min(self.stage + 1, self.num_stages)
            emit(type="enroll", phase="scanning", stage=self.stage,
                 message="Lift your finger and touch again")
            return

        if result == "enroll-completed":
            self.stage = self.num_stages
            self.finish_operation()
            emit(type="enroll", phase="done", stage=self.stage,
                 message="Fingerprint added")
            self.report_enrolled()
            return

        if result in ENROLL_RETRY and not done:
            emit(type="enroll", phase="scanning", stage=self.stage,
                 message=ENROLL_RETRY[result])
            return

        message = (ENROLL_RETRY.get(result) or ENROLL_FATAL.get(result)
                   or "Enrollment failed")
        self.finish_operation()
        emit(type="enroll", phase="failed", stage=self.stage, message=message)

    # ── Verify ────────────────────────────────────────────────────────────

    def verify(self, finger):
        if self.operation:
            self.finish_operation()
        if not self.device and not self.find_device():
            emit(type="verify", finger=finger, phase="failed", result="error",
                 message="No fingerprint reader available")
            return

        self.operation = "verify"
        self.finger = finger
        emit(type="verify", finger=finger, phase="authorizing", result="",
             message="Waiting for authorization…")

        def claimed(_result, error):
            if error is not None:
                self.operation = ""
                emit(type="verify", finger=finger, phase="failed",
                     result="error", message=error)
                return
            self.subscribe("VerifyStatus", self.on_verify_status)

            def started(_result, start_error):
                if start_error is not None:
                    self.finish_operation()
                    emit(type="verify", finger=finger, phase="failed",
                         result="error", message=start_error)
                    return
                emit(type="verify", finger=finger, phase="scanning", result="",
                     message="Touch the reader")

            self.call_async("VerifyStart", (finger,), "(s)", started)

        self.claim(claimed)

    def on_verify_status(self, result, done):
        if self.operation != "verify":
            return
        finger = self.finger

        if result == "verify-match":
            self.finish_operation()
            emit(type="verify", finger=finger, phase="done", result="match",
                 message="Match")
            return

        if result in VERIFY_RETRY and not done:
            emit(type="verify", finger=finger, phase="scanning", result="",
                 message=VERIFY_RETRY[result])
            return

        message = (VERIFY_RETRY.get(result) or VERIFY_FATAL.get(result)
                   or "That finger doesn't match")
        self.finish_operation()
        emit(type="verify", finger=finger, phase="done",
             result="no-match" if result == "verify-no-match" else "error",
             message=message)

    # ── Deleting ──────────────────────────────────────────────────────────

    def delete(self, finger):
        if self.operation:
            self.finish_operation()
        if not self.device and not self.find_device():
            emit(type="error", message="No fingerprint reader available")
            return

        # DeleteEnrolledFinger is the only per-finger call and it needs a
        # claim; the plural one wipes the user and does not.
        def claimed(_result, error):
            if error is not None:
                emit(type="error", message=error)
                return
            self.last_error = ""
            ok = self.call(self.device, DEVICE_IF, "DeleteEnrolledFinger",
                           (finger,), "(s)")
            self.release()
            if ok is None:
                emit(type="error", message=self.last_error)
            self.report_enrolled()

        self.claim(claimed)

    def delete_all(self):
        if self.operation:
            self.finish_operation()
        if not self.device and not self.find_device():
            emit(type="error", message="No fingerprint reader available")
            return
        self.last_error = ""
        ok = self.call(self.device, DEVICE_IF, "DeleteEnrolledFingers",
                       (self.user,), "(s)", timeout=CALL_TIMEOUT_MS)
        if ok is None:
            emit(type="error", message=self.last_error)
        self.report_enrolled()

    # ── Command loop ──────────────────────────────────────────────────────

    last_error = ""

    def handle(self, line):
        try:
            command = json.loads(line)
        except ValueError:
            return
        name = command.get("cmd", "")

        if name == "refresh":
            if self.report_device():
                self.report_enrolled()
            else:
                emit(type="enrolled", fingers=[])
        elif name == "enroll":
            self.enroll(command.get("finger", ""))
        elif name == "verify":
            self.verify(command.get("finger", ""))
        elif name == "cancel":
            if self.operation:
                self.finish_operation()
        elif name == "delete":
            self.delete(command.get("finger", ""))
        elif name == "delete-all":
            self.delete_all()

    def shutdown(self):
        if self.operation:
            self.finish_operation()
        else:
            self.release()


def main():
    try:
        bridge = Bridge()
    except GLib.Error as e:
        emit(type="device", available=False, name="", numEnrollStages=5,
             scanType="press")
        emit(type="error", message=e.message)
        return 1

    loop = GLib.MainLoop()

    def on_stdin(channel, condition):
        if condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR):
            loop.quit()
            return False
        try:
            status, line, _length, _end = channel.read_line()
        except GLib.Error:
            loop.quit()
            return False
        if status == GLib.IOStatus.EOF:
            loop.quit()
            return False
        if line and line.strip():
            bridge.handle(line.strip())
        return True

    channel = GLib.IOChannel.unix_new(sys.stdin.fileno())
    channel.set_flags(GLib.IOFlags.NONBLOCK)
    GLib.io_add_watch(channel,
                      GLib.PRIORITY_DEFAULT,
                      GLib.IOCondition.IN | GLib.IOCondition.HUP
                      | GLib.IOCondition.ERR,
                      on_stdin)

    # Report what is there before anyone asks, so the page has state to draw
    # the moment it opens.
    bridge.handle('{"cmd": "refresh"}')

    try:
        loop.run()
    except KeyboardInterrupt:
        pass
    finally:
        bridge.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
