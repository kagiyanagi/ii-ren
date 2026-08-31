import "duration.js" as Duration
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    readonly property bool pRunning: TimerService.pomodoroRunning ?? false
    readonly property bool sRunning: TimerService.stopwatchRunning ?? false
    readonly property bool hasStop: TimerService.stopwatchTime > 0 || sRunning
    readonly property bool hasPomo: TimerService.pomodoroSecondsLeft > 0 && (TimerService.pomodoroSecondsLeft < TimerService.focusTime || pRunning)

    property bool showPomodoro: Config.options.bar.timers.showPomodoro
    property bool showStopwatch: Config.options.bar.timers.showStopwatch

    readonly property bool stopwatchActive: hasStop && showStopwatch
    readonly property bool timerActive: hasPomo && showPomodoro
    property bool compVisible: stopwatchActive || timerActive

    // Customizable pill metrics:
    property int pillHeight: 26        // Height of the capsule pill
    property int pillPadding: 10       // Horizontal padding on both outer ends
    property int itemSpacing: 10       // Spacing between Stopwatch and Timer when merged
    property int iconSize: Appearance.font.pixelSize.normal // Icon size (16px)

    implicitWidth: pillContainer.implicitWidth
    implicitHeight: root.pillHeight

    onCompVisibleChanged: {
        if (typeof rootItem !== "undefined") {
            rootItem.toggleVisible(compVisible);
        }
    }

    Component.onCompleted: {
        if (typeof rootItem !== "undefined") {
            rootItem.isolated = true;
            rootItem.customHighlightColor = "transparent";
            rootItem.toggleHighlight(true);
            rootItem.toggleVisible(compVisible);
        }
    }

    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Rectangle {
        id: pillContainer
        anchors.centerIn: parent
        height: root.pillHeight
        implicitWidth: contentRow.implicitWidth + (root.pillPadding * 2)
        implicitHeight: root.pillHeight
        radius: Appearance.rounding.full
        color: Appearance.colors.colTimerChip

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: (root.stopwatchActive && root.timerActive) ? root.itemSpacing : 0

            Item {
                id: stopwatchItem
                visible: root.stopwatchActive
                implicitWidth: visible ? stopwatchRow.implicitWidth + 6 : 0
                implicitHeight: root.pillHeight - 2

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.full
                    color: stopwatchMouse.pressed ? Appearance.colors.colTimerChipActive : (stopwatchMouse.containsMouse ? Appearance.colors.colTimerChipHover : "transparent")
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                RowLayout {
                    id: stopwatchRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        text: root.sRunning ? "timer" : "timer_pause"
                        fill: 1
                        color: Appearance.colors.colOnTimerChip
                        iconSize: root.iconSize
                    }

                    StyledText {
                        text: Duration.format10ms(TimerService.stopwatchTime, false)
                        color: Appearance.colors.colOnTimerChip
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        font.family: Appearance.font.family.numbers
                        font.features: ({ "tnum": 1 })
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                MouseArea {
                    id: stopwatchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            TimerService.stopwatchReset();
                        } else {
                            TimerService.toggleStopwatch();
                        }
                    }
                }
            }

            Item {
                id: timerItem
                visible: root.timerActive
                implicitWidth: visible ? timerRow.implicitWidth + 6 : 0
                implicitHeight: root.pillHeight - 2

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.full
                    color: timerMouse.pressed ? Appearance.colors.colTimerChipActive : (timerMouse.containsMouse ? Appearance.colors.colTimerChipHover : "transparent")
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                RowLayout {
                    id: timerRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        text: root.pRunning ? "hourglass_bottom" : "hourglass_empty"
                        fill: 1
                        color: Appearance.colors.colOnTimerChip
                        iconSize: root.iconSize
                    }

                    StyledText {
                        text: Duration.format(TimerService.pomodoroSecondsLeft)
                        color: Appearance.colors.colOnTimerChip
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        font.family: Appearance.font.family.numbers
                        font.features: ({ "tnum": 1 })
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                MouseArea {
                    id: timerMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            TimerService.resetPomodoro();
                        } else {
                            TimerService.togglePomodoro();
                        }
                    }
                }
            }
        }
    }
}