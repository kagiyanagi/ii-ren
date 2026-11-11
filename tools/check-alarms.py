#!/usr/bin/env python3
"""Alarms keep a durable deadline, so sleep and restarts cannot skip a minute.

Run AlarmService.qml's real scheduling and CRUD functions with a controlled local
clock and persistent state. Cover overdue dated reminders, undated one-shots,
weekdays and midnight, restart deduplication, simultaneous alarms, and rearming.
The ringing alarm keeps a durable identity while other alarms are added, edited,
or deleted; old saved alarms acquire unique IDs without changing their deadlines.
No notifications or sounds reach the desktop.
"""
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
src = (II / "services/AlarmService.qml").read_text()
index_binding = re.search(r"readonly property int ringingAlarmIndex: ([^\n]+)", src).group(1)
alarm_binding = re.search(r"(?:readonly )?property var ringingAlarm: ([^\n]+)", src).group(1)
functions = re.findall(r"^    function (\w+)\([^\n]*\) \{\n.*?^    \}", src, re.M | re.S)
js = []
for name in functions:
    function = re.search(rf"^    function {name}\([^\n]*\) \{{\n.*?^    \}}", src, re.M | re.S).group()
    js.append(function.replace(f"function {name}", f"root.{name} = function", 1) + ";")

subprocess.run(["node", "-e", """
const assert = require('assert/strict');
const NativeDate = Date;
let clock = 0;
global.Date = class extends NativeDate {
    constructor(...args) { super(...(args.length ? args : [clock])); }
    static now() { return clock; }
};
const at = (day, hour, minute, second = 0) => new NativeDate(2026, 10, day, hour, minute, second).getTime();
const Qt = {formatDate: d => `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`};
const Persistent = {ready: true, states: {alarms: []}};
const Config = {options: {sounds: {alarm: false}, time: {alarms: {useFullscreenPopup: false}}}};
const GlobalStates = {alarmRinging: false};
const SoundService = {stopLoop() {}};
const notifications = [];
const Quickshell = {execDetached: c => notifications.push(c)};
const Translation = {tr: s => s};
const root = {alarms: [], ringingAlarmId: ''};
const indexBinding = INDEX_BINDING;
Object.defineProperty(root, 'ringingAlarmIndex', {get: new Function('root', 'with (root) { return (' + indexBinding + '); }').bind(null, root)});
Object.defineProperty(root, 'ringingAlarm', {get: new Function('root', 'with (root) { return (' + ALARM_BINDING + '); }').bind(null, root)});
with (root) {
""".replace("INDEX_BINDING", json.dumps(index_binding)).replace("ALARM_BINDING", json.dumps(alarm_binding)) + "\n".join(js) + """
}
function reset(alarms = []) {
    root.alarms = Persistent.states.alarms = JSON.parse(JSON.stringify(alarms));
    root.ringingAlarmId = '';
    GlobalStates.alarmRinging = false;
    notifications.length = 0;
}
const none = Array(7).fill(false), monday = [false,true,false,false,false,false,false];

clock = at(9, 9, 10);
reset([{time:'09:00', label:'dated', days:none, date:'2026-11-09', enabled:true}]);
root.checkAlarms();
assert.equal(root.ringingAlarmIndex, 0, 'overdue dated reminder was missed');
root.stopRinging();
assert.equal(root.alarms[0].enabled, false);

clock = at(8, 23, 59);
reset();
root.addAlarm('00:01', 'one-shot', none);
root.checkAlarms();
assert.equal(root.ringingAlarmIndex, -1, 'fired before deadline');
const saved = JSON.parse(JSON.stringify(Persistent.states.alarms));
clock = at(9, 0, 5);
reset(saved); // Shell was absent across the exact minute.
root.checkAlarms();
assert.equal(root.ringingAlarmIndex, 0, 'restart across midnight lost one-shot');
assert.equal(root.alarms[0].enabled, false, 'one-shot is not consumed durably at trigger');
reset(Persistent.states.alarms);
root.checkAlarms();
assert.equal(root.ringingAlarmIndex, -1, 'restart rang a consumed one-shot twice');

clock = at(8, 23, 59);
reset();
root.addAlarm('00:01', 'weekly', monday);
root.checkAlarms();
clock = at(9, 0, 5);
root.checkAlarms();
assert.equal(root.ringingAlarmIndex, 0, 'resume across weekday boundary lost recurring alarm');
root.stopRinging();
root.checkAlarms();
assert.equal(root.ringingAlarmIndex, -1, 'recurring alarm rang twice');
assert.equal(root.alarms[0].nextTrigger, at(16, 0, 1));
clock = at(23, 12, 0); // Missed multiple weeks: one catch-up, then the next future occurrence.
root.checkAlarms();
assert.equal(root.ringingAlarmIndex, 0);
assert.equal(root.alarms[0].nextTrigger, at(30, 0, 1));

clock = at(9, 8, 59);
reset();
root.addAlarm('09:00', 'first', none);
root.addAlarm('09:00', 'second', none);
clock = at(9, 9, 0, 30);
root.checkAlarms();
assert.equal(root.ringingAlarmIndex, 0);
root.stopRinging();
root.checkAlarms();
assert.equal(root.ringingAlarmIndex, 1, 'second alarm in the same minute was suppressed');
root.stopRinging();
root.checkAlarms();
assert.equal(root.ringingAlarmIndex, -1);

clock = at(9, 10, 0);
root.toggleAlarm(0); // Reenable: schedule the next occurrence, not the old missed one.
assert.equal(root.alarms[0].nextTrigger, at(10, 9, 0));
root.editAlarm(0, '11:00', 'edited', none);
const edited = root.alarms.findIndex(a => a.label === 'edited');
assert.equal(root.alarms[edited].nextTrigger, at(9, 11, 0));
root.toggleAlarm(edited);
clock = at(9, 12, 0);
root.checkAlarms();
assert.equal(root.ringingAlarmIndex, -1, 'disabled alarm fired');
reset([{time:'invalid', label:'broken', days:none, enabled:true}]);
root.checkAlarms();
assert.equal(root.ringingAlarmIndex, -1);
console.log('ok: deadlines survive sleep and restart, one-shots fire once, weekdays and simultaneous alarms survive');

// Deleting a preceding alarm must move the ringing row and its Stop control.
clock = at(9, 8, 0);
reset();
root.addAlarm('08:00', 'earlier', none);
root.addAlarm('09:00', 'ringing', monday);
root.triggerAlarm(1);
const ringingId = root.ringingAlarm.id;
root.deleteAlarm(0);
assert.equal(root.ringingAlarmIndex, 0, 'deleting before the ringing alarm lost its index');
assert.equal(root.ringingAlarm?.label, 'ringing');
assert.equal(root.ringingAlarm.id, ringingId);
assert.equal(GlobalStates.alarmRinging, true);
root.toggleAlarm(0);
assert.equal(GlobalStates.alarmRinging, false, 'disabling the shifted ringing row did not stop it');
assert.equal(root.ringingAlarmIndex, -1);
assert.equal(root.ringingAlarm, null);

// Neither adding an earlier alarm nor sorting an edited alarm changes identity.
reset();
root.addAlarm('09:00', 'ringing', monday);
root.triggerAlarm(0);
const activeId = root.ringingAlarm.id;
root.addAlarm('08:00', 'other', none);
assert.equal(root.ringingAlarmIndex, 1, 'adding an earlier alarm moved the Stop control to the new row');
assert.equal(root.ringingAlarm.id, activeId);
root.editAlarm(0, '10:00', 'other later', none);
assert.equal(root.ringingAlarmIndex, 0, 'editing another alarm lost the ringing row');
assert.equal(root.ringingAlarm.id, activeId);
root.editAlarm(0, '11:00', 'ringing edited', monday);
assert.equal(root.ringingAlarmIndex, 1, 'editing the ringing alarm did not move its Stop control');
assert.equal(root.ringingAlarm.id, activeId);
assert.equal(root.ringingAlarm.label, 'ringing edited');
root.deleteAlarm(0);
assert.equal(root.ringingAlarmIndex, 0);
assert.equal(GlobalStates.alarmRinging, true);
root.deleteAlarm(0);
assert.equal(GlobalStates.alarmRinging, false, 'deleting the ringing alarm did not stop its sound');
assert.equal(root.ringingAlarmIndex, -1);
assert.equal(root.ringingAlarm, null);

// Migration preserves valid IDs, repairs duplicates, and never rearms deadlines.
const deadline = at(10, 9, 0);
const legacy = {time:'09:00',label:'legacy',days:monday,date:'',enabled:true,nextTrigger:deadline};
reset([{...legacy,id:'kept'}, {...legacy,id:'kept'}, {...legacy}, {...legacy,id:42}]);
root.restoreAlarms();
const ids = root.alarms.map(a => a.id);
assert.equal(ids[0], 'kept');
assert(ids.every(id => typeof id === 'string' && id.length > 0));
assert.equal(new Set(ids).size, ids.length, 'migration left duplicate alarm IDs');
assert(root.alarms.every(a => a.nextTrigger === deadline && a.enabled));
root.addAlarm('09:00', 'same minute', monday);
assert.equal(new Set(root.alarms.map(a => a.id)).size, root.alarms.length, 'same-tick alarm addition reused an ID');
const persisted = JSON.parse(JSON.stringify(Persistent.states.alarms));
reset(persisted);
root.restoreAlarms();
assert.deepEqual(root.alarms, persisted, 'restart changed migrated IDs or deadlines');
console.log('ok: ringing identity survives deletion and sorting; legacy IDs migrate without rearming');
"""], check=True)

# The public index is a QML binding, not imperative bookkeeping. Exercise it in
# Qt as Persistent becomes ready and CRUD replaces the typed list<var> values.
with tempfile.TemporaryDirectory(prefix="ii-alarms-") as directory:
    path = Path(directory)
    service = re.sub(r"^import qs(?:\.[\w.]+)?\n", "", src, flags=re.M)
    service = service.replace("import QtQuick", 'import "."\nimport QtQuick', 1)
    # No missed assertion may reach a desktop notification or real sound.
    service = service.replace("Quickshell.execDetached", "SoundService.unexpectedNotification")
    (path / "AlarmService.qml").write_text(service)
    stubs = {
        "Persistent": "property bool ready: false; property var states: ({alarms: []})",
        "Config": "property var options: ({sounds: {alarm: false}, time: {alarms: {useFullscreenPopup: true}}})",
        "GlobalStates": "property bool alarmRinging: false; property bool screenLocked: false",
        "Translation": "function tr(s) { return s; }",
        "SoundService": '''property int stops: 0
            function stopLoop() { stops++; }
            function startLoop() { throw new Error("Unexpected sound request"); }
            function unexpectedNotification() { throw new Error("Unexpected desktop notification"); }''',
    }
    for name, body in stubs.items():
        (path / f"{name}.qml").write_text(f"pragma Singleton\nimport QtQuick\nQtObject {{\n{body}\n}}\n")
    (path / "qmldir").write_text("\n".join(
        f"singleton {name} 1.0 {name}.qml" for name in ["AlarmService", *stubs]
    ))
    (path / "shell.qml").write_text('''import QtQuick
import Quickshell
import "."
ShellRoot {
    function check(condition, message) {
        if (!condition) throw new Error(message);
    }
    function run() {
        try {
            AlarmService.load();
            const deadline = Date.now() + 86400000;
            const days = [true, true, true, true, true, true, true];
            Persistent.states = {alarms: [
                {time:"08:00", label:"other", days:days, enabled:true, nextTrigger:deadline},
                {time:"09:00", label:"active", days:days, enabled:true, nextTrigger:deadline}
            ]};
            Persistent.ready = true;
            check(AlarmService.alarms.every(a => a.id && a.nextTrigger === deadline), "ready-time migration changed deadlines or missed IDs");
            AlarmService.triggerAlarm(1);
            const id = AlarmService.ringingAlarm.id;
            AlarmService.deleteAlarm(0);
            check(AlarmService.ringingAlarmIndex === 0 && AlarmService.ringingAlarm.id === id, "delete did not update derived index");
            AlarmService.addAlarm("08:00", "added", days);
            check(AlarmService.ringingAlarmIndex === 1 && AlarmService.ringingAlarm.id === id, "add did not update derived index");
            AlarmService.editAlarm(0, "10:00", "edited", days);
            check(AlarmService.ringingAlarmIndex === 0 && AlarmService.ringingAlarm.id === id, "edit did not update derived index");
            AlarmService.toggleAlarm(0);
            check(!GlobalStates.alarmRinging && AlarmService.ringingAlarmIndex === -1 && AlarmService.ringingAlarm === null, "shifted active row did not stop");
            AlarmService.triggerAlarm(0);
            AlarmService.deleteAlarm(0);
            check(!GlobalStates.alarmRinging && AlarmService.ringingAlarmIndex === -1, "active deletion did not stop");
            console.log("ALARM_QT_OK");
        } catch (error) {
            console.error(error);
        }
        Qt.quit();
    }
    Component.onCompleted: Qt.callLater(run)
}
''')
    result = subprocess.run(["qs", "-p", str(path), "--no-color"], capture_output=True, text=True,
                            env=dict(os.environ, QT_QPA_PLATFORM="offscreen"), timeout=8)
    output = result.stdout + result.stderr
    assert result.returncode == 0 and "ALARM_QT_OK" in output, output
    assert not re.search(r"ReferenceError|TypeError|Unable to assign|Error:", output), output
print("ok: Qt migrates on readiness and keeps the ringing index bound to stable identity")
