#!/usr/bin/env python3
"""Notification replacements go through the same delivery policy as new arrivals.

Quickshell emits NotificationServer.notification only for new objects. Replacing
one updates its properties instead, so bound text changed on screen while sound,
popup lifetime and the saved copy stayed at the first delivery. A multi-field
replacement must deliver once, retain the same wrapper and restart its timer;
hint-only progress and action-label updates must also reach that path.

Run the actual services/Notifications.qml with small dependency stubs, a private
D-Bus session and temporary files. Real Notify calls exercise Qt's property
signals, bindings, callLater coalescing and timers; the desktop is untouched.

Run: python3 tools/check-notifications.py
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path
from textwrap import dedent
from types import SimpleNamespace

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
SOURCE = (II / "services/Notifications.qml").read_text()


def wait_for(read, predicate, why, seconds=5):
    end = time.monotonic() + seconds
    value = None
    while time.monotonic() < end:
        try:
            value = read()
            if predicate(value):
                return value
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            pass
        time.sleep(0.02)
    raise AssertionError(f"{why}; last value: {value}")


@contextmanager
def service(saved="[]"):
    with tempfile.TemporaryDirectory(prefix="ii-notifications-") as directory:
        path = Path(directory)
        notifications = path / "notifications.json"
        history = path / "history.json"
        notifications.write_text(saved)
        history.write_text("[]")
        # Keep the service intact apart from its shell-specific import paths.
        qml = re.sub(r"^import qs(?:\.[\w.]+)?\n", "", SOURCE, flags=re.M)
        (path / "Notifications.qml").write_text(qml.replace("import QtQuick", 'import "."\nimport QtQuick', 1))
        stubs = {
            "Config": '''property var options: ({ notifications: {
                cooldown: false, timeout: 900, history: { enable: true }
            } })''',
            "GlobalStates": "property bool sidebarRightOpen: false",
            "Directories": f'''property string notificationsPath: {json.dumps(str(notifications))}
                property string notificationHistoryPath: {json.dumps(str(history))}''',
            "Appearance": "property var animationCurves: ({ expressiveSlowSpatialDuration: 650 })",
            "SoundService": '''property int calls: 0
                property var events: ({ notifications: ["message"] })
                function playEvent(event, sounds) { calls++; }''',
        }
        for name, body in stubs.items():
            (path / f"{name}.qml").write_text(f"pragma Singleton\nimport QtQuick\nQtObject {{\n{body}\n}}\n")
        (path / "qmldir").write_text("\n".join(
            f"singleton {name} 1.0 {name}.qml" for name in ["Notifications", *stubs]
        ))
        (path / "shell.qml").write_text(dedent('''\
            import QtQuick
            import Quickshell
            import Quickshell.Io
            import "."

            ShellRoot {
                id: probe
                property bool initialized: false
                property int deliveries: 0
                Connections {
                    target: Notifications
                    function onInitDone() { probe.initialized = true; }
                    function onNotify(notification) { probe.deliveries++; }
                }
                IpcHandler {
                    target: "test"
                    function state(): string {
                        return JSON.stringify({
                            initialized: probe.initialized,
                            deliveries: probe.deliveries,
                            sounds: SoundService.calls,
                            unread: Notifications.unread,
                            groups: Notifications.appNameList,
                            items: Notifications.list.map(n => ({
                                id: n.notificationId, summary: n.summary, body: n.body,
                                appName: n.appName, time: n.time, popup: n.popup,
                                actions: n.actions, tracked: n.notification !== null,
                                timer: n.timer ? { running: n.timer.running, interval: n.timer.interval } : null
                            }))
                        });
                    }
                    function silent(value: bool): void { Notifications.silent = value; }
                    function cooldown(value: bool): void { Config.options.notifications.cooldown = value; }
                    function hide(id: int): void { Notifications.timeoutNotification(id); }
                    function discard(id: int): void { Notifications.discardNotification(id); }
                }
            }
        '''))
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
        with (path / "log").open("w") as log:
            process = subprocess.Popen(["qs", "-p", str(path), "--no-color"], env=env,
                                       stdout=log, stderr=subprocess.STDOUT)

            def call(method, *args):
                return subprocess.run(
                    ["qs", "ipc", "--pid", str(process.pid), "call", "test", method, *map(str, args)],
                    env=env, text=True, capture_output=True, check=True, timeout=5,
                ).stdout.strip()

            probe = SimpleNamespace(call=call, state=lambda: json.loads(call("state")),
                                    notifications=notifications, history=history)
            try:
                wait_for(probe.state, lambda s: s["initialized"], "notification history never loaded")
                yield probe
            except BaseException:
                print((path / "log").read_text(), file=sys.stderr)
                raise
            finally:
                process.terminate()
                process.wait(timeout=5)


def notify(replaces=0, summary="First", body="First body", app="Test app", timeout=1200,
           hints="{}", actions="['open', 'Open']"):
    result = subprocess.run([
        "gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
        "--object-path", "/org/freedesktop/Notifications",
        "--method", "org.freedesktop.Notifications.Notify", app, str(replaces), "",
        summary, body, actions, hints, str(timeout),
    ], text=True, capture_output=True, check=True, timeout=5)
    return int(re.search(r"uint32 (\d+)", result.stdout).group(1))


def check_replacements():
    with service() as probe:
        server_id = notify()
        first = wait_for(probe.state, lambda s: len(s["items"]) == 1, "new notification missing")
        wrapper_id = first["items"][0]["id"]
        assert first["sounds"] == first["deliveries"] == 1
        time.sleep(0.5)
        assert notify(server_id, "Updated", "Updated body", timeout=2000,
                      hints="{'value': <50>}") == server_id
        updated = wait_for(probe.state, lambda s: s["deliveries"] == 2,
                           "replacement did not deliver exactly once")
        assert len(updated["items"]) == 1, "replacement duplicated the row"
        item = updated["items"][0]
        assert item["id"] == wrapper_id and item["time"] > first["items"][0]["time"]
        assert item["summary"] == "Updated" and item["body"] == "Updated body"
        assert updated["sounds"] == 2 and item["popup"]
        assert item["timer"] == {"running": True, "interval": 2000}
        wait_for(lambda: json.loads(probe.notifications.read_text()),
                 lambda saved: len(saved) == 1 and saved[0]["body"] == "Updated body",
                 "replacement text was not saved")
        wait_for(lambda: json.loads(probe.history.read_text()),
                 lambda saved: len(saved) == 2 and saved[-1]["summary"] == "Updated",
                 "replacement was not recorded in history")
        time.sleep(0.9)  # Past the original deadline, before the replacement's.
        assert probe.state()["items"][0]["popup"], "the original timer expired the replacement"
        wait_for(probe.state, lambda s: not s["items"][0]["popup"], "replacement never timed out")

        notify(server_id, "Updated", "Updated body", timeout=0, hints="{'value': <75>}")
        progress = wait_for(probe.state, lambda s: s["deliveries"] == 3, "hint-only update was ignored")
        assert progress["items"][0]["popup"] and progress["items"][0]["timer"] is None
        assert progress["sounds"] == 3

        notify(server_id, "Updated", "Updated body", timeout=0, hints="{'value': <75>}",
               actions="['open', 'Read']")
        relabeled = wait_for(probe.state, lambda s: s["deliveries"] == 4, "action-label update was ignored")
        assert relabeled["items"][0]["actions"] == [{"identifier": "open", "text": "Read"}]

        probe.call("silent", "true")
        notify(server_id, "Quiet", timeout=0)
        quiet = wait_for(probe.state, lambda s: s["deliveries"] == 5, "DND dropped the update")
        assert quiet["sounds"] == 4 and not quiet["items"][0]["popup"], "replacement bypassed DND"
        probe.call("silent", "false")
        notify(server_id, "Visible", timeout=0)
        wait_for(probe.state, lambda s: s["deliveries"] == 6, "replacement failed to reappear")
        probe.call("cooldown", "true")
        notify(server_id, "Still visible", timeout=2000)
        cooled = wait_for(probe.state, lambda s: s["deliveries"] == 7, "cooldown dropped the update")
        assert cooled["sounds"] == 5 and cooled["items"][0]["popup"], "cooldown hid a visible popup"
        assert cooled["items"][0]["timer"]["running"]
        probe.call("hide", wrapper_id)
        notify(server_id, "Still quiet", timeout=0)
        hidden = wait_for(probe.state, lambda s: s["deliveries"] == 8, "hidden replacement was ignored")
        assert hidden["sounds"] == 5 and not hidden["items"][0]["popup"], "cooldown was bypassed"

        probe.call("cooldown", "false")
        notify(app="Other app", timeout=0)
        wait_for(probe.state, lambda s: s["groups"] == ["Other app", "Test app"],
                 "new app was not sorted first")
        notify(server_id, "Latest in existing group", timeout=0)
        wait_for(probe.state, lambda s: s["groups"] == ["Test app", "Other app"],
                 "replacement left an existing app group sorted by its old timestamp")
        notify(server_id, "Renamed", app="Renamed app", timeout=0)
        renamed = wait_for(probe.state, lambda s: s["groups"] == ["Renamed app", "Other app"],
                           "replacement did not refresh app grouping and ordering")
        assert len(renamed["items"]) == 2
    print("ok: replacements refresh delivery, timers and persistence once; DND and cooldown hold")


if __name__ == "__main__":
    if "--private-bus" not in sys.argv:
        subprocess.run(["dbus-run-session", "--", sys.executable, __file__, "--private-bus"], check=True)
    else:
        check_replacements()
