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

    implicitWidth: 24
    implicitHeight: pillContainer.implicitHeight

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

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Rectangle {
        id: pillContainer
        anchors.centerIn: parent
        width: 24
        implicitWidth: 24
        implicitHeight: contentColumn.implicitHeight + 20
        radius: Appearance.rounding.full
        color: Appearance.colors.colTimerChip

        ColumnLayout {
            id: contentColumn
            anchors.centerIn: parent
            spacing: (root.stopwatchActive && root.timerActive) ? 10 : 0

            Item {
                id: stopwatchItem
                visible: root.stopwatchActive
                implicitWidth: 22
                implicitHeight: visible ? stopwatchCol.implicitHeight + 6 : 0
                Layout.alignment: Qt.AlignHCenter

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.full
                    color: stopwatchMouse.pressed ? Appearance.colors.colTimerChipActive : (stopwatchMouse.containsMouse ? Appearance.colors.colTimerChipHover : "transparent")
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                ColumnLayout {
                    id: stopwatchCol
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.sRunning ? "timer" : "timer_pause"
                        fill: 1
                        color: Appearance.colors.colOnTimerChip
                        iconSize: Appearance.font.pixelSize.normal
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: {
                            const sec = Math.floor(TimerService.stopwatchTime / 100);
                            return Math.floor(sec / 60).toString().padStart(2, '0') + "\n" + (sec % 60).toString().padStart(2, '0');
                        }
                        color: Appearance.colors.colOnTimerChip
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        font.family: Appearance.font.family.numbers
                        font.features: ({ "tnum": 1 })
                        horizontalAlignment: Text.AlignHCenter
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
                implicitWidth: 22
                implicitHeight: visible ? timerCol.implicitHeight + 6 : 0
                Layout.alignment: Qt.AlignHCenter

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.full
                    color: timerMouse.pressed ? Appearance.colors.colTimerChipActive : (timerMouse.containsMouse ? Appearance.colors.colTimerChipHover : "transparent")
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                ColumnLayout {
                    id: timerCol
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.pRunning ? "hourglass_bottom" : "hourglass_empty"
                        fill: 1
                        color: Appearance.colors.colOnTimerChip
                        iconSize: Appearance.font.pixelSize.normal
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: {
                            const t = TimerService.pomodoroSecondsLeft;
                            return Math.floor(t / 60).toString().padStart(2, '0') + "\n" + (t % 60).toString().padStart(2, '0');
                        }
                        color: Appearance.colors.colOnTimerChip
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        font.family: Appearance.font.family.numbers
                        font.features: ({ "tnum": 1 })
                        horizontalAlignment: Text.AlignHCenter
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