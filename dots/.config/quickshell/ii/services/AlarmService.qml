pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property list<var> alarms: Persistent.ready ? (Persistent.states.alarms ?? []) : []
    // CRUD sorts and splices the list. Keep identity independent of its position,
    // while exposing the current index for the existing rows and Stop controls.
    property string ringingAlarmId: ""
    readonly property int ringingAlarmIndex: root.ringingAlarmId ? root.alarms.findIndex(alarm => alarm.id === root.ringingAlarmId) : -1
    readonly property var ringingAlarm: root.ringingAlarmIndex >= 0 ? root.alarms[root.ringingAlarmIndex] : null

    // Instantiated at shell startup so deadlines are armed before a popup is opened.
    function load() {}

    function repeats(alarm) {
        return !alarm.date && (alarm.days?.includes(true) ?? false);
    }

    function nextOccurrence(alarm, after) {
        if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(alarm.time)) return 0;
        const [hour, minute] = alarm.time.split(":").map(Number);
        if (alarm.date) {
            if (!/^\d{4}-\d{2}-\d{2}$/.test(alarm.date)) return 0;
            const [year, month, day] = alarm.date.split("-").map(Number);
            // Construct in local time; parsing YYYY-MM-DD would use UTC.
            return new Date(year, month - 1, day, hour, minute).getTime();
        }
        const start = new Date(after);
        for (let offset = 0; offset <= 7; offset++) {
            const candidate = new Date(start.getFullYear(), start.getMonth(), start.getDate() + offset, hour, minute);
            if (candidate.getTime() > after && (!root.repeats(alarm) || alarm.days[candidate.getDay()]))
                return candidate.getTime();
        }
        return 0;
    }

    function armAlarm(alarm) {
        const minute = new Date();
        minute.setSeconds(0, 0);
        alarm.nextTrigger = root.nextOccurrence(alarm, minute.getTime() - 1);
    }

    function withAlarmIds(alarms) {
        // Reserve every saved ID first, including later entries. Same-tick
        // additions and duplicate legacy IDs must never steal another row's ID.
        const used = new Set(alarms.map(alarm => alarm.id).filter(id => typeof id === "string" && id.length > 0));
        const seen = new Set();
        const prefix = `alarm-${Date.now().toString(36)}-`;
        let serial = 0;
        return alarms.map(alarm => {
            let id = alarm.id;
            if (typeof id !== "string" || id.length === 0 || seen.has(id)) {
                do { id = prefix + (++serial); } while (used.has(id));
                used.add(id);
            }
            seen.add(id);
            return Object.assign({}, alarm, { id });
        });
    }

    function saveAlarms(newAlarms) {
        const identified = root.withAlarmIds(newAlarms);
        if (root.ringingAlarmId && !identified.some(alarm => alarm.id === root.ringingAlarmId))
            root.stopRinging();
        Persistent.states.alarms = identified;
        root.alarms = Persistent.states.alarms ?? [];
    }

    function restoreAlarms() {
        if (!Persistent.ready) return;
        const saved = Persistent.states.alarms ?? [];
        const identified = root.withAlarmIds(saved);
        // ID migration changes no scheduling data and writes only once.
        if (identified.some((alarm, index) => alarm.id !== saved[index].id))
            root.saveAlarms(identified);
        else
            root.alarms = saved;
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            root.restoreAlarms();
        }
    }

    function toggleAlarm(index) {
        if (!Persistent.ready) return;
        let cloned = JSON.parse(JSON.stringify(Persistent.states.alarms));
        if (index >= 0 && index < cloned.length) {
            cloned[index].enabled = !cloned[index].enabled;
            if (cloned[index].enabled) root.armAlarm(cloned[index]);
            if (!cloned[index].enabled && cloned[index].id === root.ringingAlarmId) {
                stopRinging();
            }
            saveAlarms(cloned);
        }
    }

    function addAlarm(time, label, days, date = "") {
        if (!Persistent.ready) return false;
        let cloned = JSON.parse(JSON.stringify(Persistent.states.alarms || []));
        cloned.push({
            time: time || "08:00",
            label: label || Translation.tr("Alarm"),
            days: days || [false, false, false, false, false, false, false],
            // Empty means the original recurring/one-shot behaviour. A
            // YYYY-MM-DD value makes this a reminder for that local date and
            // avoids an alarm requested for tomorrow firing today at the same
            // time.
            date: date || "",
            enabled: true
        });
        root.armAlarm(cloned[cloned.length - 1]);
        cloned.sort((a, b) => a.time.localeCompare(b.time));
        saveAlarms(cloned);
        return true;
    }

    function editAlarm(index, time, label, days) {
        if (!Persistent.ready) return;
        let cloned = JSON.parse(JSON.stringify(Persistent.states.alarms));
        if (index >= 0 && index < cloned.length) {
            cloned[index].time = time;
            cloned[index].label = label;
            cloned[index].days = days;
            cloned[index].enabled = true;
            root.armAlarm(cloned[index]);
            cloned.sort((a, b) => a.time.localeCompare(b.time));
            saveAlarms(cloned);
        }
    }

    function deleteAlarm(index) {
        if (!Persistent.ready) return;
        let cloned = JSON.parse(JSON.stringify(Persistent.states.alarms));
        if (index >= 0 && index < cloned.length) {
            if (cloned[index].id === root.ringingAlarmId) {
                stopRinging();
            }
            cloned.splice(index, 1);
            saveAlarms(cloned);
        }
    }

    function triggerAlarm(index) {
        if (!Persistent.ready || index < 0 || index >= alarms.length) return;

        // Consume before ringing, not on dismissal: a restart cannot replay the
        // same one-shot or recurring occurrence. Collapse missed repeats into one.
        const cloned = root.withAlarmIds(JSON.parse(JSON.stringify(alarms)));
        const alarm = cloned[index];
        if (root.repeats(alarm)) {
            cloned[index].nextTrigger = root.nextOccurrence(alarm, Date.now());
        } else {
            cloned[index].enabled = false;
            cloned[index].nextTrigger = 0;
        }
        root.saveAlarms(cloned);
        root.ringingAlarmId = alarm.id;

        // Play sound in loop if enabled
        SoundService.stopLoop();
        if (Config.options.sounds.alarm) {
            const fadeSeconds = Config.options.sounds.alarmFadeIn ? Config.options.sounds.alarmFadeInSeconds : 0;
            SoundService.startLoop("alarm", "alarm-clock-elapsed", fadeSeconds);
        }

        // A locked session cannot show the popup; keep a notification in its
        // history as well as the ringing sound until the user unlocks.
        if (!Config.options.time.alarms.useFullscreenPopup || GlobalStates.screenLocked) {
            let labelStr = alarm.label ? alarm.label : Translation.tr("Alarm");
            Quickshell.execDetached(["notify-send", labelStr, alarm.time, "-a", "Alarm", "-i", "alarm", "--urgency=critical", "--hint=boolean:suppress-sound:true"]);
        }

        GlobalStates.alarmRinging = true;
    }

    function stopRinging() {
        if (!root.ringingAlarmId) return;

        root.ringingAlarmId = "";
        SoundService.stopLoop();
        GlobalStates.alarmRinging = false;
    }

    function checkAlarms() {
        if (!Persistent.ready || !alarms || alarms.length === 0) return;
        const now = Date.now();
        const cloned = root.withAlarmIds(JSON.parse(JSON.stringify(alarms)));
        let changed = cloned.some((alarm, index) => alarm.id !== alarms[index].id);
        let due = -1;
        for (let i = 0; i < cloned.length; i++) {
            const alarm = cloned[i];
            if (!alarm.enabled) continue;
            // Migrate old alarms once. Dated reminders retain their original
            // deadline, including overdue ones; undated alarms arm from now.
            if (alarm.nextTrigger === undefined) {
                root.armAlarm(alarm);
                changed = true;
            }
            if (alarm.nextTrigger > 0 && alarm.nextTrigger <= now
                    && (due === -1 || alarm.nextTrigger < cloned[due].nextTrigger))
                due = i;
        }
        if (changed) root.saveAlarms(cloned);
        if (due !== -1 && !root.ringingAlarmId) root.triggerAlarm(due);
    }

    Timer {
        id: alarmCheckTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: checkAlarms()
    }

    Timer {
        id: autoStopTimer
        interval: 300000 // 5 minutes
        running: root.ringingAlarmId !== ""
        repeat: false
        onTriggered: stopRinging()
    }

    IpcHandler {
        target: "alarmService"
        function trigger(index: int): void {
            root.triggerAlarm(index);
        }
        function add(time: string, label: string): void {
            root.addAlarm(time, label, [true, true, true, true, true, true, true]);
        }
        function stop(): void {
            root.stopRinging();
        }
    }

    Component.onCompleted: root.restoreAlarms()
}
