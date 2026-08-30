#!/usr/bin/env python3
"""Camera, screen sharing and location users, as one JSON line per state change.

Mostly event driven rather than polled. The Pipewire graph arrives once from a
single long-lived `pw-dump --monitor` and is kept up to date from the same
stream, so nothing reconnects to Pipewire on a timer - reconnecting is itself a
graph change, and a watcher that reacts to graph changes by reconnecting will
happily chase its own tail. A direct open of a /dev/video* node arrives from
inotify. Only GeoClue is still asked on a tick, because it is one cheap D-Bus
call and there is no signal to hang it on.

The poll loop this replaced cost about 8% of a core around the clock, three
quarters of it `fuser` rescanning every process's file descriptors twice a
second.

The microphone comes straight from Pipewire in QML, so it isn't watched here.
"""

import ctypes
import json
import os
import select
import signal
import subprocess
import sys
import time

# Long enough to swallow the burst of events a single app start produces,
# short enough that the indicator still feels immediate.
DEBOUNCE = 0.25
# GeoClue has no signal we can watch, so it keeps the cadence the old poll loop
# gave it. One NameHasOwner call is a few milliseconds.
TICK = 2.0
# Belt and braces for an event source that dropped something. The expensive
# scan only runs here and on an inotify event, so it stays rare.
RECONCILE = 30.0

IN_OPEN = 0x20
IN_CLOSE_WRITE = 0x08
IN_CLOSE_NOWRITE = 0x10
PR_SET_PDEATHSIG = 1

# These hold the camera on behalf of whoever asked through Pipewire, and that
# app is already in the stream list.
PIPEWIRE_OWN = {"pipewire", "wireplumber", "pipewire-pulse"}


def die_with_parent():
    """Quickshell doesn't reap us when it's killall'd; without this, every
    shell restart leaks another copy of this watcher."""
    try:
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(PR_SET_PDEATHSIG, signal.SIGTERM)
    except OSError:
        pass  # The getppid check in the main loop still covers us.


def video_nodes():
    try:
        return sorted("/dev/" + n for n in os.listdir("/dev") if n.startswith("video"))
    except OSError:
        return []


class VideoWatch:
    """inotify on the camera nodes. IN_OPEN fires the moment a process opens
    one, which is the only way to see an app that bypasses Pipewire without
    walking every process in /proc on a timer."""

    def __init__(self):
        self.libc = ctypes.CDLL("libc.so.6", use_errno=True)
        self.fd = self.libc.inotify_init1(os.O_NONBLOCK)
        if self.fd < 0:
            self.fd = -1
            return
        for dev in video_nodes():
            self.libc.inotify_add_watch(
                self.fd, dev.encode(), IN_OPEN | IN_CLOSE_WRITE | IN_CLOSE_NOWRITE
            )

    def drain(self):
        if self.fd < 0:
            return
        try:
            os.read(self.fd, 65536)
        except OSError:
            pass


class PwGraph:
    """The Pipewire graph, kept current from one `pw-dump --monitor`.

    The monitor writes a full dump as a JSON array, then one array per batch of
    changes; a removed object comes back as {"id": N, "info": null}. Batches are
    delimited by a `]` alone on a line, which is what we split on.
    """

    def __init__(self):
        self.objects = {}
        self.buf = b""
        try:
            self.proc = subprocess.Popen(
                ["pw-dump", "--monitor", "--no-colors"],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
            )
        except OSError:
            self.proc = None

    @property
    def stdout(self):
        return self.proc.stdout if self.proc else None

    def feed(self):
        """Read what is waiting and apply any complete batches. Returns None on
        EOF, otherwise whether the graph changed."""
        chunk = os.read(self.stdout.fileno(), 1 << 16)
        if not chunk:
            return None  # pw-dump died; the caller drops us.
        self.buf += chunk
        return self.feed_buffer()

    def feed_buffer(self):
        changed = False
        while True:
            end = self.buf.find(b"\n]\n")
            if end < 0:
                break
            batch, self.buf = self.buf[: end + 2], self.buf[end + 3 :]
            try:
                objects = json.loads(batch)
            except ValueError:
                continue  # Not a batch boundary after all; drop it and move on.
            for obj in objects:
                oid = obj.get("id")
                if obj.get("info") is None and "info" in obj:
                    self.objects.pop(oid, None)
                else:
                    self.objects[oid] = obj
            changed = True
        return changed


def camera_holders():
    """PIDs with a /dev/video* node open, by device number rather than by name
    so a symlinked node still matches. This is what `fuser /dev/video*` did,
    without its extra pass over every process's cwd, root, exe and maps."""
    devs = set()
    for dev in video_nodes():
        try:
            devs.add(os.stat(dev).st_rdev)
        except OSError:
            pass
    if not devs:
        return []

    holders = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fddir = "/proc/" + pid + "/fd"
        try:
            fds = os.listdir(fddir)
        except OSError:
            continue  # Gone, or not ours to look at.
        for fd in fds:
            try:
                if os.stat(fddir + "/" + fd).st_rdev not in devs:
                    continue
            except OSError:
                continue
            comm = read_comm(pid)
            if comm and comm not in PIPEWIRE_OWN:
                holders.append({"name": comm, "pid": int(pid)})
            break
    return holders


def read_comm(pid):
    try:
        with open("/proc/" + str(pid) + "/comm") as f:
            return f.read().strip()
    except OSError:
        return ""


def classify_streams(dump):
    """A video consumer says nothing about what it is consuming, so follow its
    driver back to the source: a v4l2/Camera source is the webcam, anything
    else (the desktop portal) is a screen cast."""
    sources = {}
    clients = []
    for obj in dump:
        info = obj.get("info") or {}
        props = info.get("props") or {}
        cls = props.get("media.class", "")
        if cls == "Video/Source":
            sources[obj.get("id")] = props
        elif cls == "Stream/Input/Video" and info.get("state") == "running":
            clients.append(props)

    cameras, screens = [], []
    for props in clients:
        src = sources.get(props.get("node.driver-id") or props.get("node.target")) or {}
        entry = {
            "name": props.get("node.name") or props.get("application.name") or "?",
            "pid": props.get("application.process.id") or 0,
        }
        if src.get("media.role") == "Camera" or src.get("device.api") == "v4l2":
            cameras.append(entry)
        else:
            screens.append(entry)
    return cameras, screens


def busctl_true(args):
    try:
        out = subprocess.run(
            ["busctl", "--system"] + args, capture_output=True, timeout=10, text=True
        ).stdout
        return "b true" in out
    except (OSError, subprocess.SubprocessError):
        return False


def location_state():
    """Asking GeoClue for a property would D-Bus-activate it, so only ask when
    it is already up."""
    if not busctl_true(
        [
            "call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus", "NameHasOwner", "s", "org.freedesktop.GeoClue2",
        ]
    ):
        return False, []
    if not busctl_true(
        [
            "get-property", "org.freedesktop.GeoClue2",
            "/org/freedesktop/GeoClue2/Manager",
            "org.freedesktop.GeoClue2.Manager", "InUse",
        ]
    ):
        return False, []

    # GeoClue only lets a client read its own DesktopId, so name the clients by
    # who has a geoclue library mapped instead. Apps that talk to GeoClue over
    # raw D-Bus stay anonymous.
    apps = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open("/proc/" + pid + "/maps") as f:
                if "geoclue" not in f.read():
                    continue
        except OSError:
            continue
        # The agent is GeoClue's own permission prompt, not a consumer.
        try:
            if "geoclue" in os.readlink("/proc/" + pid + "/exe"):
                continue
        except OSError:
            pass
        comm = read_comm(pid)
        if comm:
            apps.append({"name": comm, "pid": int(pid)})
    return True, apps


def by_name(entries):
    seen, out = set(), []
    for e in sorted(entries, key=lambda e: e["name"]):
        if e["name"] not in seen:
            seen.add(e["name"])
            out.append(e)
    return out


def selftest():
    dump = [
        {"id": 1, "info": {"props": {"media.class": "Video/Source", "device.api": "v4l2"}}},
        {"id": 2, "info": {"props": {"media.class": "Video/Source", "media.role": "Screen"}}},
        {"id": 3, "info": {"state": "running", "props": {
            "media.class": "Stream/Input/Video", "node.driver-id": 1,
            "node.name": "webcam-app", "application.process.id": 42}}},
        {"id": 4, "info": {"state": "running", "props": {
            "media.class": "Stream/Input/Video", "node.target": 2,
            "application.name": "sharer", "application.process.id": 43}}},
        {"id": 5, "info": {"state": "idle", "props": {
            "media.class": "Stream/Input/Video", "node.driver-id": 1,
            "node.name": "not-running"}}},
    ]
    cams, screens = classify_streams(dump)
    assert cams == [{"name": "webcam-app", "pid": 42}], cams
    assert screens == [{"name": "sharer", "pid": 43}], screens
    # A node that is not running must not light the indicator.
    assert all(e["name"] != "not-running" for e in cams + screens)
    assert by_name([{"name": "b", "pid": 2}, {"name": "a", "pid": 1}, {"name": "a", "pid": 9}]) == [
        {"name": "a", "pid": 1}, {"name": "b", "pid": 2}]

    # The monitor stream: a full dump, then an update, then a removal.
    g = PwGraph.__new__(PwGraph)
    g.objects, g.buf, g.proc = {}, b"", None

    def feed(text):
        g.buf += text.encode()
        return g.feed_buffer()

    assert feed('[\n{"id":3,"info":{"state":"idle"}}\n]\n')
    assert g.objects[3]["info"]["state"] == "idle"
    assert feed('[\n{"id":3,"info":{"state":"running"}}\n]\n')
    assert g.objects[3]["info"]["state"] == "running", g.objects
    assert feed('[\n{"id":3,"info":null}\n]\n')
    assert 3 not in g.objects, g.objects
    print("selftest ok")


def main():
    if "--selftest" in sys.argv:
        return selftest()

    die_with_parent()
    parent = os.getppid()
    watch = VideoWatch()
    graph = PwGraph()

    sources = [f for f in (watch.fd if watch.fd >= 0 else None, graph.stdout) if f is not None]

    last = None
    holders, location, apps = [], False, []
    rescan = True  # The starting state has to come from somewhere.
    now = time.monotonic()
    next_tick, next_reconcile = now, now + RECONCILE
    pending = True

    while True:
        if os.getppid() != parent:
            return

        now = time.monotonic()
        if pending:
            timeout = DEBOUNCE
        else:
            timeout = max(0.0, min(next_tick, next_reconcile) - now)

        ready, _, _ = select.select(sources, [], [], timeout)
        if ready:
            for src in ready:
                if src == watch.fd:
                    watch.drain()
                    rescan = True  # Someone opened or closed a camera node.
                elif graph.feed() is None:
                    sources.remove(src)  # pw-dump died; the reconcile carries on.
            pending = True
            continue  # Keep coalescing until the burst stops.

        now = time.monotonic()
        if now >= next_reconcile:
            next_reconcile = now + RECONCILE
            rescan = True
        if now >= next_tick:
            next_tick = now + TICK
            location, apps = location_state()

        if rescan:
            # Apps that open the device themselves never appear as a stream.
            holders = camera_holders()
            rescan = False

        pending = False
        cameras, screens = classify_streams(graph.objects.values())
        state = {
            "camera": by_name(cameras + holders),
            "screen": sorted(screens, key=lambda e: e["name"]),
            "location": location,
            "apps": apps,
        }
        if state != last:
            last = state
            print(json.dumps(state, separators=(",", ":")), flush=True)


if __name__ == "__main__":
    main()
