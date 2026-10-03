pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * A nice wrapper for date and time strings.
 */
Singleton {
    id: root

    property var clock: SystemClock {
        id: clock
        precision: {
            if (Config.options?.time?.secondPrecision
                || Config.options?.bar?.clock?.showSeconds
                || (Config.options?.bar?.clock?.timeFormat && Config.options.bar.clock.timeFormat.includes("s"))
                || GlobalStates.screenLocked)
                return SystemClock.Seconds;
            return SystemClock.Minutes;
        }
    }
    property string seconds: Qt.locale().toString(clock.date, Config.options?.time.secondsFormat ?? "ss")
    property string time: Qt.locale().toString(clock.date, Config.options?.time.format ?? "hh:mm")
    property string shortDate: Qt.locale().toString(clock.date, Config.options?.time.shortDateFormat ?? "dd/MM")
    property string date: Qt.locale().toString(clock.date, Config.options?.time.dateWithYearFormat ?? "dd/MM/yyyy")
    property string longDate: Qt.locale().toString(clock.date, Config.options?.time.dateFormat ?? "dddd, dd/MM")
    property string collapsedCalendarFormat: Qt.locale().toString(clock.date, "dddd, MMMM dd")
    // Boot time from /proc/uptime once; the minute-precision clock above then drives the
    // string, rather than re-reading the file every few seconds for a minute-wide value.
    property real bootTime: 0
    property string uptime: {
        if (root.bootTime === 0)
            return "0h, 0m";
        const uptimeSeconds = Math.max(0, (clock.date.getTime() - root.bootTime) / 1000);
        const days = Math.floor(uptimeSeconds / 86400);
        const hours = Math.floor((uptimeSeconds % 86400) / 3600);
        const minutes = Math.floor((uptimeSeconds % 3600) / 60);
        let formatted = "";
        if (days > 0)
            formatted += `${days}d`;
        if (hours > 0)
            formatted += `${formatted ? ", " : ""}${hours}h`;
        if (minutes > 0 || !formatted)
            formatted += `${formatted ? ", " : ""}${minutes}m`;
        return formatted;
    }

    FileView {
        id: fileUptime
        path: "/proc/uptime"
        onLoaded: root.bootTime = Date.now() - Number(fileUptime.text().split(" ")[0] ?? 0) * 1000
    }
}
