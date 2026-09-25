import "../../bar/duration.js" as Duration
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    Item {
        anchors {
            fill: parent
            rightMargin: 12
            bottomMargin: 12
        }

        CircularProgress {
            anchors.centerIn: ringArea
            lineWidth: 8
            value: TimerService.pomodoroSecondsLeft / TimerService.focusTime
            implicitSize: 200
            enableAnimation: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                // Click to type a duration. Only while idle: a running lap counts
                // down from a start timestamp, so typed digits would be
                // overwritten on the next tick.
                StyledTextInput {
                    id: timeInput
                    Layout.alignment: Qt.AlignHCenter
                    text: Duration.format(TimerService.pomodoroSecondsLeft)
                    font.pixelSize: Appearance.font.pixelSize.huge * 2
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: ({})
                    font.features: ({ "tnum": 1 })
                    color: Appearance.m3colors.m3onSurface
                    horizontalAlignment: Text.AlignHCenter
                    readOnly: TimerService.pomodoroRunning
                    activeFocusOnPress: !readOnly
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: RegularExpressionValidator {
                        regularExpression: /^\d{0,2}(:\d{0,2}){0,2}$/
                    }
                    onEditingFinished: {
                        const seconds = Duration.parse(text);
                        if (seconds > 0)
                            Config.options.time.pomodoro.focus = seconds;
                        // Typing broke the binding; put it back either way.
                        text = Qt.binding(() => Duration.format(TimerService.pomodoroSecondsLeft));
                        focus = false;
                    }
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    visible: !TimerService.pomodoroRunning
                    text: TimerService.pomodoroSecondsLeft === TimerService.focusTime ? Translation.tr("Click to set") : Translation.tr("Paused")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
        }

        Item {
            id: ringArea
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                bottom: controls.top
            }
        }

        RowLayout {
            id: controls
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            spacing: 8
            uniformCellSizes: true

            TimerButton {
                iconName: "restart_alt"
                buttonText: Translation.tr("Reset")
                enabled: TimerService.pomodoroRunning || TimerService.pomodoroSecondsLeft < TimerService.focusTime
                onClicked: TimerService.resetPomodoro()
            }
            TimerButton {
                filled: true
                iconName: TimerService.pomodoroRunning ? "pause" : "play_arrow"
                buttonText: TimerService.pomodoroRunning ? Translation.tr("Pause") : TimerService.pomodoroSecondsLeft === TimerService.focusTime ? Translation.tr("Start") : Translation.tr("Resume")
                buttonRadius: TimerService.pomodoroRunning ? Appearance.rounding.small : Math.min(Appearance.rounding.full, implicitHeight / 2)
                onClicked: TimerService.togglePomodoro()
            }
        }
    }
}
