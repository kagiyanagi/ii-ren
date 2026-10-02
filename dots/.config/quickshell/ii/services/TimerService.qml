pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common

import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Simple countdown timer + stopwatch.
 */
Singleton {
    id: root

    property int focusTime: Config.options.time.pomodoro.focus

    property bool pomodoroRunning: Persistent.states.timer.pomodoro.running
    property int pomodoroSecondsLeft: focusTime // Reasonable init value, to be changed

    property bool stopwatchRunning: Persistent.states.timer.stopwatch.running
    property int stopwatchTime: 0
    property real stopwatchStart: Persistent.states.timer.stopwatch.start
    property var stopwatchLaps: Persistent.states.timer.stopwatch.laps

    // Config durations can change at any time; while idle the displayed time is a
    // plain value, not a binding, so it has to be pulled back in sync by hand.
    onFocusTimeChanged: {
        if (!pomodoroRunning)
            resetPomodoro();
    }

    // General
    Component.onCompleted: {
        if (!stopwatchRunning)
            stopwatchReset();
    }

    function getCurrentTimeInSeconds() {  // Timer uses seconds
        return Math.floor(Date.now() / 1000);
    }

    function getCurrentTimeIn10ms() {  // Stopwatch uses 10ms
        return Math.floor(Date.now() / 10);
    }

    // Timer
    function refreshPomodoro() {
        if (getCurrentTimeInSeconds() >= Persistent.states.timer.pomodoro.start + focusTime) {
            // The timer's own sound stands in for the notification's when it is on.
            const quiet = Config.options.sounds.enable && Config.options.sounds.pomodoro ? ["--hint=boolean:suppress-sound:true"] : [];
            Quickshell.execDetached(["notify-send", "Timer", Translation.tr(`⏰ %1 minutes are up`).arg(Math.floor(focusTime / 60)), "-a", "Shell", ...quiet]);
            SoundService.playEvent("pomodoro");
            resetPomodoro();
            return;
        }

        pomodoroSecondsLeft = focusTime - (getCurrentTimeInSeconds() - Persistent.states.timer.pomodoro.start);
    }

    Timer {
        id: pomodoroTimer
        interval: 200
        running: root.pomodoroRunning
        repeat: true
        onTriggered: refreshPomodoro()
    }

    function togglePomodoro() {
        Persistent.states.timer.pomodoro.running = !pomodoroRunning;
        if (Persistent.states.timer.pomodoro.running) {
            // Start/Resume
            Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds() + pomodoroSecondsLeft - focusTime;
        }
    }

    function resetPomodoro() {
        Persistent.states.timer.pomodoro.running = false;
        Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds();
        pomodoroSecondsLeft = focusTime;
    }

    // Stopwatch
    function refreshStopwatch() {  // Stopwatch stores time in 10ms
        stopwatchTime = getCurrentTimeIn10ms() - stopwatchStart;
    }

    // The bar and the clock popup show whole seconds, so this only has to be
    // close; the sidebar's centiseconds run off their own FrameAnimation.
    Timer {
        id: stopwatchTimer
        interval: 100
        running: root.stopwatchRunning
        repeat: true
        onTriggered: refreshStopwatch()
    }

    function toggleStopwatch() {
        if (root.stopwatchRunning)
            stopwatchPause();
        else
            stopwatchResume();
    }

    function stopwatchPause() {
        refreshStopwatch();
        Persistent.states.timer.stopwatch.running = false;
    }

    function stopwatchResume() {
        if (stopwatchTime === 0) Persistent.states.timer.stopwatch.laps = [];
        // Start before running: anything that samples on the running edge
        // would otherwise read the last run's start for a frame.
        Persistent.states.timer.stopwatch.start = getCurrentTimeIn10ms() - stopwatchTime;
        Persistent.states.timer.stopwatch.running = true;
    }

    function stopwatchReset() {
        stopwatchTime = 0;
        Persistent.states.timer.stopwatch.laps = [];
        Persistent.states.timer.stopwatch.running = false;
    }

    function stopwatchRecordLap() {
        refreshStopwatch();
        Persistent.states.timer.stopwatch.laps.push(stopwatchTime);
    }
}
