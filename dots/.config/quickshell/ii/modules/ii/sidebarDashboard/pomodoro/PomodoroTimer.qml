import "../../bar/duration.js" as Duration
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    implicitHeight: contentColumn.implicitHeight
    implicitWidth: contentColumn.implicitWidth

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        spacing: 0

        // The timer circle
        CircularProgress {
            Layout.alignment: Qt.AlignHCenter
            lineWidth: 8
            value: {
                return TimerService.pomodoroSecondsLeft / TimerService.focusTime;
            }
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
                    font.pixelSize: 40
                    color: Appearance.m3colors.m3onSurface
                    horizontalAlignment: Text.AlignHCenter
                    readOnly: TimerService.pomodoroRunning
                    activeFocusOnPress: !readOnly
                    inputMethodHints: Qt.ImhPreferNumbers
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
                    text: Translation.tr("Click to set")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
            }

        }

        // The Start/Stop and Reset buttons
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            RippleButton {
                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: TimerService.pomodoroRunning ? Translation.tr("Pause") : (TimerService.pomodoroSecondsLeft === TimerService.focusTime) ? Translation.tr("Start") : Translation.tr("Resume")
                    color: TimerService.pomodoroRunning ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                }
                implicitHeight: 35
                implicitWidth: 90
                font.pixelSize: Appearance.font.pixelSize.larger
                onClicked: TimerService.togglePomodoro()
                colBackground: TimerService.pomodoroRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
                colBackgroundHover: TimerService.pomodoroRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
            }

            RippleButton {
                implicitHeight: 35
                implicitWidth: 90

                onClicked: TimerService.resetPomodoro()
                enabled: TimerService.pomodoroSecondsLeft < TimerService.focusTime

                font.pixelSize: Appearance.font.pixelSize.larger
                colBackground: Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colErrorContainerHover
                colRipple: Appearance.colors.colErrorContainerActive

                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Reset")
                    color: Appearance.colors.colOnErrorContainer
                }
            }
        }
    }
}
