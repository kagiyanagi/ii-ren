#!/usr/bin/env python3
"""The sidebar stopwatch keeps exact time without a 100Hz timer.

None of this shows in a screenshot. The stopwatch's start is in 10ms ticks since the
epoch, about 1.8e11, and it was stored in a QML `int`. That only worked because the
wrapped start and the wrapped difference cancel mod 2^32 when the result lands in
another int. The readout now computes in JS doubles, so an `int` start shows garbage.
The service ticked every 10ms, which ran JS 100 times a second for as long as the
stopwatch ran, sidebar shut or not. It ticks at 100ms now, so lap and pause must take a
fresh sample or they record a time up to 100ms stale. The frame clock that draws the
centiseconds must only run while someone can see it.
"""
import re
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
persistent = (II / "modules/common/Persistent.qml").read_text()
service = (II / "services/TimerService.qml").read_text()
stopwatch = (II / "modules/ii/sidebarDashboard/pomodoro/Stopwatch.qml").read_text()
widget = (II / "modules/ii/sidebarDashboard/pomodoro/PomodoroWidget.qml").read_text()
button = (II / "modules/ii/sidebarDashboard/pomodoro/TimerButton.qml").read_text()

sw = re.search(r"property JsonObject stopwatch: JsonObject \{(.*?)\n\s*\}", persistent, re.S).group(1)
assert re.search(r"property real start\b", sw), "Persistent stopwatch.start must be real: 10ms epoch ticks overflow int"
assert re.search(r"property real stopwatchStart\b", service), "TimerService.stopwatchStart must be real"

interval = int(re.search(r"id: stopwatchTimer\s*\n\s*interval: (\d+)", service).group(1))
assert interval >= 100, f"stopwatch service timer at {interval}ms -- the bar shows seconds; the frame clock does the rest"

for fn in ("stopwatchPause", "stopwatchRecordLap"):
    body = re.search(rf"function {fn}\(\) \{{(.*?)\n    \}}", service, re.S).group(1)
    assert "refreshStopwatch()" in body.split("Persistent")[0], f"{fn} must sample before it stores"

running = re.search(r"FrameAnimation \{.*?running: ([^\n]+)", stopwatch, re.S).group(1)
for guard in ("TimerService.stopwatchRunning", "GlobalStates.sidebarRightOpen", "SwipeView.isCurrentItem"):
    assert guard in running, f"frame clock must be gated on {guard}"
assert "Timer {" not in stopwatch, "no Timer in the stopwatch view -- it has a frame clock"

# L used to record a lap from either tab, paused or not, pushing a stale time.
assert re.search(r"Key_L && tabBar\.currentIndex === 1 && TimerService\.stopwatchRunning", widget)

# AbstractButton.icon is FINAL: redeclaring it makes the type unavailable, and both tabs with it.
assert not re.search(r"property \w+ icon\b", button), "TimerButton must not redeclare `icon`"

print("check-pomodoro: ok")
