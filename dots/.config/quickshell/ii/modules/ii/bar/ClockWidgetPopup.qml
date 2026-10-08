import "duration.js" as Duration
import qs.modules.common
import qs.modules.common.widgets
import "./cards"
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

StyledPopup {
    id: root
    keyboardFocus: alarmsCard.mode !== "list" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property var timezoneOffsets: ({})
    property var worldClocksOption: Config.options.time.worldClocks
    onWorldClocksOptionChanged: {
        root.refreshTimezoneOffsets();
    }

    function refreshTimezoneOffsets() {
        let timezones = Config.options.time.worldClocks || [];
        if (timezones.length === 0) {
            root.timezoneOffsets = {};
            return;
        }

        let script = "";
        for (let i = 0; i < timezones.length; i++) {
            let tz = timezones[i].tz;
            if (tz) {
                let safeTz = tz.replace(/'/g, "'\\''");
                script += `TZ='${safeTz}' date +'%H:%M %z %Z ${safeTz}'; `;
            }
        }

        if (script === "") {
            root.timezoneOffsets = {};
            return;
        }

        _worldClocksProcess.offsetFetcher.command = ["bash", "-c", script];
        _worldClocksProcess.offsetFetcher.running = true;
    }

    property QtObject _worldClocksProcess: QtObject {
        property Process offsetFetcher: Process {
            stdout: StdioCollector {
                id: offsetCollector
                onStreamFinished: {
                    let lines = offsetCollector.text.split("\n");
                    let newOffsets = {};
                    for (let i = 0; i < lines.length; i++) {
                        let line = lines[i].trim();
                        if (!line) continue;
                        let parts = line.split(" ");
                        if (parts.length >= 4) {
                            let timeStr = parts[0];
                            let offsetStr = parts[1];
                            let tzName = parts[2];
                            let tz = parts.slice(3).join(" ");

                            let sign = offsetStr.charAt(0) === "-" ? -1 : 1;
                            let hours = parseInt(offsetStr.substring(1, 3));
                            let mins = parseInt(offsetStr.substring(3, 5));
                            let offsetMins = sign * (hours * 60 + mins);

                            newOffsets[tz] = {
                                offsetMins: offsetMins,
                                tzName: tzName
                            };
                        }
                    }
                    root.timezoneOffsets = newOffsets;
                }
            }
        }
    }

    stickyHover: true

    /*
     * Which sections draw, read by the stagger and by `contentAvailable`
     * (an empty popup is a 400px-wide card under the pointer).
     *
     * These live on the root and not on the column that draws them, because
     * the column is inside the LazyLoader's content: it exists only while the
     * popup is open. A `contentAvailable` that asked the content whether the
     * content was worth showing could answer only once -- after the first
     * close the ids are gone, the binding throws, and the popup never opens
     * again. Every condition here is a config or singleton read, so none of
     * them needs the content to be alive.
     */
    readonly property bool hasClockFace: Config.options.time.alarms.showAnalogClock
    readonly property bool hasWorldClocks: Config.options.time.alarms.showWorldClocks
        && Config.options.time.worldClocks && Config.options.time.worldClocks.length > 0
    readonly property bool hasInfoColumn: true // the timer pill never hides
    readonly property bool hasTransfer: LocalSend.droppedFiles.length > 0
    readonly property bool hasAlarms: Config.options.time.alarms.showAlarmsSection

    contentAvailable: !Config.ready || root.hasClockFace || root.hasWorldClocks
        || root.hasInfoColumn || root.hasTransfer || root.hasAlarms

    property bool stopwatchPaused: !TimerService.stopwatchRunning && TimerService.stopwatchTime > 0

    function formatTimerDisplay(seconds) {
        let m = Math.floor(seconds / 60);
        let s = seconds % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    function getUtcTimeForTz(tz, date) {
        try {
            const data = root.timezoneOffsets[tz];
            if (!data) return NaN;
            return date.getTime() + (data.offsetMins * 60000);
        } catch (e) {
            return NaN;
        }
    }

    function getTimezoneOffsetString(tz, date) {
        try {
            const data = root.timezoneOffsets[tz];
            if (!data) return "";

            const localOffsetMins = -date.getTimezoneOffset();
            const targetOffsetMins = data.offsetMins;

            const diffMins = targetOffsetMins - localOffsetMins;
            if (diffMins === 0) {
                return "";
            }

            const diffHrs = diffMins / 60;
            const sign = diffHrs > 0 ? "+" : "";

            if (diffMins % 60 === 0) {
                return sign + diffHrs + "h";
            }

            const hrs = Math.floor(Math.abs(diffMins) / 60);
            const mins = Math.abs(diffMins) % 60;
            return `${sign}${diffHrs < 0 ? "-" : ""}${hrs}h ${mins}m`;
        } catch (e) {
            return "";
        }
    }

    function getFormattedTime(tz, date) {
        try {
            const data = root.timezoneOffsets[tz];
            if (!data) return "--:--";

            const offsetMins = data.offsetMins;
            const targetDate = new Date(date.getTime() + (offsetMins * 60000));

            const formatStr = Config.options?.time?.format ?? "hh:mm";
            const use12h = formatStr.includes("ap") || formatStr.includes("AP");
            const showSeconds = Config.options?.time?.secondPrecision ?? false;

            let hour = targetDate.getUTCHours();
            let minute = targetDate.getUTCMinutes();
            let second = targetDate.getUTCSeconds();

            let ampm = "";
            if (use12h) {
                ampm = hour >= 12 ? (formatStr.includes("AP") ? " PM" : " pm") : (formatStr.includes("AP") ? " AM" : " am");
                hour = hour % 12 || 12;
            }

            let hrStr = String(hour).padStart(2, "0");
            let minStr = String(minute).padStart(2, "0");
            let secStr = showSeconds ? ":" + String(second).padStart(2, "0") : "";

            return hrStr + ":" + minStr + secStr + ampm;
        } catch (e) {
            return "--:--";
        }
    }

    function getFormattedDate(tz, date) {
        try {
            const data = root.timezoneOffsets[tz];
            if (!data) return "";

            const offsetMins = data.offsetMins;
            const targetDate = new Date(date.getTime() + (offsetMins * 60000));

            const dateFormatStr = Config.options?.time?.dateFormat ?? "ddd dd/MM";
            const showMonthFirst = dateFormatStr.includes("MM/dd");

            const days = [Translation.tr("Sun"), Translation.tr("Mon"), Translation.tr("Tue"), Translation.tr("Wed"), Translation.tr("Thu"), Translation.tr("Fri"), Translation.tr("Sat")];
            const weekday = days[targetDate.getUTCDay()];

            const day = String(targetDate.getUTCDate()).padStart(2, "0");
            const month = String(targetDate.getUTCMonth() + 1).padStart(2, "0");

            if (showMonthFirst) {
                return `${weekday} ${month}/${day}`;
            } else {
                return `${weekday} ${day}/${month}`;
            }
        } catch (e) {
            return "";
        }
    }

    /*
     * Contract 1's one entrance rule (DESIGN.md 2.8), the same shape every popup
     * in this cluster uses: opacity on an effects spec, one transform on the
     * enter spatial spec, siblings offset by their place in the visible order.
     * `running` is bound to the popup's open state, so a close stops it
     * mid-flight and the `from:` values restore the start state on the next open.
     * That is the whole of the reset that `resetContentEntrance()`,
     * `startContentEntrance()` and the `_entranceGeneration` counter used to do
     * by hand.
     *
     * Exit is the surface's own arrowPopup close, inherited from StyledPopup;
     * the content does not animate out separately.
     */
    component EnterAnim: SequentialAnimation {
        id: enterAnim

        property Item item
        property Translate slide
        property int delay: 0
        readonly property int offset: 12

        PauseAnimation {
            duration: enterAnim.delay
        }
        ParallelAnimation {
            NumberAnimation {
                target: enterAnim.item
                property: "opacity"
                from: 0
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
            NumberAnimation {
                target: enterAnim.slide
                property: "y"
                from: enterAnim.offset
                to: 0
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
        }
    }

    contentItem: ColumnLayout {
        id: columnLayout
        anchors.centerIn: parent
        implicitWidth: 400
        spacing: 12

        // Delays computed dynamically based on visibility order to prevent stagger skipping
        readonly property var _visList: [
            root.hasClockFace,
            root.hasWorldClocks,
            root.hasInfoColumn,
            root.hasTransfer,
            root.hasAlarms
        ]

        // Counted over *visible* siblings: with a section hidden by config,
        // counting raw indices would leave a hole in the sequence and the tail
        // would enter late for no reason on screen.
        function getDelay(index) {
            let visIndex = 0;
            for (let i = 0; i < index; i++) {
                if (_visList[i]) visIndex++;
            }
            return Appearance.animation.staggerStep * Math.min(visIndex, Appearance.animation.staggerCap);
        }

        readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6

        ClockHeaderCard {
            id: clockHero
            Layout.fillWidth: true
            Layout.minimumWidth: 400
            visible: root.hasClockFace
            startAnim: columnLayout.startAnim
            
            opacity: 0
            transform: Translate {
                id: clockHeroTransform
            }

            EnterAnim {
                item: clockHero
                slide: clockHeroTransform
                delay: columnLayout.getDelay(0)
                running: columnLayout.startAnim
            }
        }

        Loader {
            id: worldClocksLoader
            Layout.fillWidth: true
            Layout.minimumWidth: 360
            visible: root.hasWorldClocks
            active: root.hasWorldClocks
            sourceComponent: worldClocksComponent
            
            opacity: 0
            transform: Translate {
                id: worldClocksTransform
            }

            EnterAnim {
                item: worldClocksLoader
                slide: worldClocksTransform
                delay: columnLayout.getDelay(1)
                running: columnLayout.startAnim
            }
        }

        ColumnLayout {
            id: infoColumn
            Layout.fillWidth: true
            spacing: 12
            
            opacity: 0
            transform: Translate {
                id: infoColumnTransform
            }

            EnterAnim {
                item: infoColumn
                slide: infoColumnTransform
                delay: columnLayout.getDelay(2)
                running: columnLayout.startAnim
            }

            InfoPill {
                id: infoPill
                startAnim: columnLayout.startAnim
                
                readonly property bool isTimerActive: TimerService.pomodoroRunning || TimerService.stopwatchRunning || root.stopwatchPaused || (TimerService.stopwatchTime > 0)

                textContent: Loader {
                    anchors.centerIn: parent
                    sourceComponent: TimerService.pomodoroRunning ? pomodoroText : (TimerService.stopwatchTime > 0 ? stopwatchText : timerOffText)
                }
                
                containerColor: infoPill.isTimerActive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest
                color: containerColor
                shapeColor: infoPill.isTimerActive ? Appearance.colors.colPrimary : Appearance.colors.colSecondary
                symbolColor: infoPill.isTimerActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondary
                textColor: infoPill.isTimerActive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                
                leftInteractive: true
                icon: {
                    if (infoPill.isTimerActive) {
                        if (TimerService.pomodoroRunning || TimerService.stopwatchRunning) return "pause";
                        return "play_arrow";
                    } else {
                        return infoPill.leftHovered ? "play_arrow" : "timer";
                    }
                }
                
                onLeftClicked: {
                    if (TimerService.pomodoroRunning) {
                        TimerService.togglePomodoro();
                    } else if (TimerService.stopwatchRunning || root.stopwatchPaused || TimerService.stopwatchTime > 0) {
                        TimerService.toggleStopwatch();
                    } else {
                        TimerService.toggleStopwatch();
                    }
                }

                showRightShape: infoPill.isTimerActive
                rightIcon: "stop"
                rightShapeColor: Appearance.colors.colErrorContainer
                rightSymbolColor: Appearance.colors.colOnErrorContainer
                
                onRightClicked: {
                    TimerService.stopwatchReset();
                    if (TimerService.pomodoroRunning) {
                        TimerService.resetPomodoro();
                    }
                }
            }
        }

        Loader {
            id: localSendLoader
            Layout.fillWidth: true
            Layout.minimumWidth: 360
            visible: active
            active: root.hasTransfer
            sourceComponent: LocalSendSendCard {}
            
            opacity: 0
            transform: Translate {
                id: localSendTransform
            }

            EnterAnim {
                item: localSendLoader
                slide: localSendTransform
                delay: columnLayout.getDelay(3)
                running: columnLayout.startAnim
            }
        }

        AlarmsCard {
            id: alarmsCard
            Layout.fillWidth: true
            Layout.minimumWidth: 360
            visible: root.hasAlarms
            startAnim: columnLayout.startAnim
            
            opacity: 0
            transform: Translate {
                id: alarmsCardTransform
            }

            EnterAnim {
                item: alarmsCard
                slide: alarmsCardTransform
                delay: columnLayout.getDelay(4)
                running: columnLayout.startAnim
            }
        }

        Component {
            id: timerOffText
            StyledText {
                text: Translation.tr("Timer off")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                font.weight: Font.Bold
            }
        }

        Component {
            id: pomodoroText
            StyledText {
                visible: TimerService.pomodoroRunning
                text: root.formatTimerDisplay(TimerService.pomodoroSecondsLeft)
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                font.weight: Font.Bold
            }
        }

        Component {
            id: stopwatchText
            RowLayout {
                id: textLayout
                visible: TimerService.stopwatchTime > 0
                width: 70 // To prevent shakiness
                anchors.centerIn: parent
                spacing: 0

                SequentialAnimation {
                    running: root.stopwatchPaused
                    loops: Animation.Infinite

                    ScriptAction { script: textLayout.visible = true }
                    // design-ok: a blink cadence for a paused stopwatch, not a
                    // transition -- there is no motion token for "how often".
                    PauseAnimation { duration: 700 }
                    ScriptAction { script: textLayout.visible = false }
                    // design-ok: the other half of the same blink cadence.
                    PauseAnimation { duration: 700 }

                    onStopped: {
                        if (TimerService.stopwatchTime <= 0) return
                        textLayout.visible = true
                    }
                }

                StyledText {
                    color: Appearance.m3colors.m3onSurface
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    font.weight: Font.Bold

                    text: Duration.format10ms(TimerService.stopwatchTime)
                }

                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    font.weight: Font.Bold

                    text: {
                        return `:<sub>${(Math.floor(TimerService.stopwatchTime) % 100).toString().padStart(2, '0')}</sub>`
                    }
                }
            }
        }


        Component {
            id: worldClocksComponent
            WorldClocksCard {
                timezoneOffsets: root.timezoneOffsets
                getTimezoneOffsetString: root.getTimezoneOffsetString
                getUtcTimeForTz: root.getUtcTimeForTz
                getFormattedTime: root.getFormattedTime
                getFormattedDate: root.getFormattedDate
                startAnim: columnLayout.startAnim
            }
        }


    }
}
