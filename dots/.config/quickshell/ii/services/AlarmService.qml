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
    property int ringingAlarmIndex: -1
    property var ringingAlarm: (ringingAlarmIndex >= 0 && alarms && ringingAlarmIndex < alarms.length) ? alarms[ringingAlarmIndex] : null

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

    function saveAlarms(newAlarms) {
        Persistent.states.alarms = newAlarms;
        root.alarms = Persistent.states.alarms ?? [];
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready) {
                root.alarms = Persistent.states.alarms ?? [];
            }
        }
    }

    function toggleAlarm(index) {
        if (!Persistent.ready) return;
        let cloned = JSON.parse(JSON.stringify(Persistent.states.alarms));
        if (index >= 0 && index < cloned.length) {
            cloned[index].enabled = !cloned[index].enabled;
            if (cloned[index].enabled) root.armAlarm(cloned[index]);
            if (!cloned[index].enabled && ringingAlarmIndex === index) {
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
            if (ringingAlarmIndex === index) {
                stopRinging();
            }
            cloned.splice(index, 1);
            saveAlarms(cloned);
        }
    }

    function triggerAlarm(index) {
        if (index < 0 || index >= alarms.length) return;

        let alarm = alarms[index];
        // Consume before ringing, not on dismissal: a restart cannot replay the
        // same one-shot or recurring occurrence. Collapse missed repeats into one.
        const cloned = JSON.parse(JSON.stringify(alarms));
        if (root.repeats(alarm)) {
            cloned[index].nextTrigger = root.nextOccurrence(alarm, Date.now());
        } else {
            cloned[index].enabled = false;
            cloned[index].nextTrigger = 0;
        }
        root.saveAlarms(cloned);
        ringingAlarmIndex = index;

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
        if (ringingAlarmIndex === -1) return;

        ringingAlarmIndex = -1;
        SoundService.stopLoop();
        GlobalStates.alarmRinging = false;
    }

    function checkAlarms() {
        if (!Persistent.ready || !alarms || alarms.length === 0) return;
        const now = Date.now();
        const cloned = JSON.parse(JSON.stringify(alarms));
        let changed = false;
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
        if (due !== -1 && ringingAlarmIndex === -1) root.triggerAlarm(due);
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
        running: ringingAlarmIndex !== -1
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

    Component.onCompleted: {
        if (Persistent.ready) {
            root.alarms = Persistent.states.alarms;
        }
    }
}
