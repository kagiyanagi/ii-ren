.pragma library

// Shared MM:SS formatting for the timer/stopwatch/pomodoro readouts.
// TimerService keeps the pomodoro in whole seconds and the stopwatch in 10ms
// ticks, hence the two entry points.

/** Whole seconds -> "MM:SS". */
function format(seconds) {
    return String(Math.floor(seconds / 60)).padStart(2, '0') + ":" + String(Math.floor(seconds % 60)).padStart(2, '0');
}

/** 10ms ticks -> "MM:SS", or "MM:SS.CC" when showFraction. */
function format10ms(ticks, showFraction) {
    const t = Math.floor(ticks);
    const out = format(Math.floor(t / 100));
    return showFraction ? out + "." + String(t % 100).padStart(2, '0') : out;
}
