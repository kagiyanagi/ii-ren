#!/usr/bin/env python3
"""Alarms keep a durable deadline, so sleep and restarts cannot skip a minute.

Run AlarmService.qml's real scheduling and CRUD functions with a controlled local
clock and persistent state. Cover overdue dated reminders, undated one-shots,
weekdays and midnight, restart deduplication, simultaneous alarms, and rearming.
No notifications or sounds reach the desktop.
"""
import re
import subprocess
from pathlib import Path

src = (Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/services/AlarmService.qml").read_text()
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
const root = {alarms: [], ringingAlarmIndex: -1, lastTriggeredMinute: ''};
with (root) {
""" + "\n".join(js) + """
}
function reset(alarms = []) {
    root.alarms = Persistent.states.alarms = JSON.parse(JSON.stringify(alarms));
    root.ringingAlarmIndex = -1;
    root.lastTriggeredMinute = '';
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
"""], check=True)
