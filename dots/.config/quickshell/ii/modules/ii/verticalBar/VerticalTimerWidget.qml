import qs.modules.common
import qs.modules.common.functions
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

    // TimerWidget's metrics, turned 90 degrees.
    property int pillWidth: 24
    property int pillPadding: 10
    property int itemSpacing: 10

    implicitWidth: root.pillWidth
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

    // No Behavior on the height: the Revealers below already animate what it
    // follows. It had one on elementMoveFast while the chips snapped with
    // `visible:`, so the pill resized around content that had already jumped.

    Rectangle {
        id: pillContainer
        anchors.centerIn: parent
        width: root.pillWidth
        implicitHeight: contentColumn.implicitHeight + root.pillPadding * 2
        radius: Appearance.rounding.full
        color: Appearance.colors.colTimerChip

        ColumnLayout {
            id: contentColumn
            anchors.centerIn: parent
            spacing: (root.stopwatchActive && root.timerActive) ? root.itemSpacing : 0

            Behavior on spacing {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            TimerChip {
                reveal: root.stopwatchActive
                icon: root.sRunning ? "timer" : "timer_pause"
                seconds: Math.floor(TimerService.stopwatchTime / 100)
                primaryAction: () => TimerService.toggleStopwatch()
                resetAction: () => TimerService.stopwatchReset()
            }

            TimerChip {
                reveal: root.timerActive
                icon: root.pRunning ? "hourglass_bottom" : "hourglass_empty"
                seconds: TimerService.pomodoroSecondsLeft
                primaryAction: () => TimerService.togglePomodoro()
                resetAction: () => TimerService.resetPomodoro()
            }
        }
    }

    component TimerChip: Revealer {
        id: chip

        required property string icon
        required property int seconds
        required property var primaryAction
        required property var resetAction

        vertical: true
        Layout.alignment: Qt.AlignHCenter

        Item {
            implicitWidth: root.pillWidth - 2
            implicitHeight: chipCol.implicitHeight + 6

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.full
                color: chipMouse.pressed ? Appearance.colors.colTimerChipActive
                    : chipMouse.containsMouse ? Appearance.colors.colTimerChipHover
                    : ColorUtils.transparentize(Appearance.colors.colTimerChipHover, 1)

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            ColumnLayout {
                id: chipCol
                anchors.centerIn: parent
                spacing: 4

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: chip.icon
                    fill: 1
                    color: Appearance.colors.colOnTimerChip
                    iconSize: Appearance.font.pixelSize.normal
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Math.floor(chip.seconds / 60).toString().padStart(2, '0') + "\n" + (chip.seconds % 60).toString().padStart(2, '0')
                    color: Appearance.colors.colOnTimerChip
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    font.family: Appearance.font.family.numbers
                    font.features: ({ "tnum": 1 })
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            MouseArea {
                id: chipMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton)
                        chip.resetAction();
                    else
                        chip.primaryAction();
                }
            }
        }
    }
}
