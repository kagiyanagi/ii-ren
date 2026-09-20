import "duration.js" as Duration
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

    // No Behavior here: the two Revealers below already animate the width this
    // follows, and a second filter on top of an animated value makes the bar
    // slot lag the pill it is meant to be the same width as.

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

            // Follows the chips' own opening spec so the gap between them and the
            // chip widths are one movement, not two (2.5).
            Behavior on spacing {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            TimerChip {
                reveal: root.stopwatchActive
                icon: root.sRunning ? "timer" : "timer_pause"
                label: Duration.format10ms(TimerService.stopwatchTime, false)
                primaryAction: () => TimerService.toggleStopwatch()
                resetAction: () => TimerService.stopwatchReset()
            }

            TimerChip {
                reveal: root.timerActive
                icon: root.pRunning ? "hourglass_bottom" : "hourglass_empty"
                label: Duration.format(TimerService.pomodoroSecondsLeft)
                primaryAction: () => TimerService.togglePomodoro()
                resetAction: () => TimerService.resetPomodoro()
            }
        }
    }

    // Revealer carries the enter/exit asymmetry a `visible:` toggle cannot: the
    // chip grew and vanished in one frame before (2.5, law 10).
    component TimerChip: Revealer {
        id: chip

        required property string icon
        required property string label
        required property var primaryAction
        required property var resetAction

        Item {
            implicitWidth: chipRow.implicitWidth + 6
            implicitHeight: root.pillHeight - 2

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.full
                // Fading to a zero-alpha copy of the hover film rather than to
                // "transparent" keeps the hue out of the midpoint of the fade.
                color: chipMouse.pressed ? Appearance.colors.colTimerChipActive
                    : chipMouse.containsMouse ? Appearance.colors.colTimerChipHover
                    : ColorUtils.transparentize(Appearance.colors.colTimerChipHover, 1)

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            RowLayout {
                id: chipRow
                anchors.centerIn: parent
                spacing: 4

                MaterialSymbol {
                    text: chip.icon
                    fill: 1
                    color: Appearance.colors.colOnTimerChip
                    iconSize: root.iconSize
                }

                StyledText {
                    text: chip.label
                    color: Appearance.colors.colOnTimerChip
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    font.family: Appearance.font.family.numbers
                    font.features: ({ "tnum": 1 })
                    verticalAlignment: Text.AlignVCenter
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