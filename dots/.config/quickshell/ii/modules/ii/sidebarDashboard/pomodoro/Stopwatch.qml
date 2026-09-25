import "../../bar/duration.js" as Duration
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: stopwatchTab
    // 10ms ticks. The service refreshes every 100ms, which the bar's seconds are
    // fine with; the centiseconds here need a frame clock, and only while seen.
    readonly property real ticks: frameClock.running ? frameClock.ticks : TimerService.stopwatchTime

    FrameAnimation {
        id: frameClock
        property real ticks
        function sample() { ticks = Date.now() / 10 - TimerService.stopwatchStart }
        running: TimerService.stopwatchRunning && GlobalStates.sidebarRightOpen && stopwatchTab.SwipeView.isCurrentItem
        onRunningChanged: sample()
        onTriggered: sample()
    }

    component Digits: StyledText {
        font.pixelSize: Appearance.font.pixelSize.huge * 2
        font.family: Appearance.font.family.numbers
        font.variableAxes: ({})
        font.features: ({ "tnum": 1 })
    }

    Item {
        anchors {
            fill: parent
            rightMargin: 12
            bottomMargin: 12
        }

        Item {
            id: readoutArea
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                bottom: controls.top
            }
        }

        RowLayout {
            id: elapsedIndicator
            anchors {
                horizontalCenter: parent.horizontalCenter
                verticalCenter: readoutArea.verticalCenter
            }
            spacing: 0

            // Laps push the readout up out of their way, as the Clock app does.
            states: State {
                name: "hasLaps"
                when: TimerService.stopwatchLaps.length > 0
                AnchorChanges {
                    target: elapsedIndicator
                    anchors.top: readoutArea.top
                    anchors.verticalCenter: undefined
                }
            }
            transitions: Transition {
                AnchorAnimation {
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            Digits {
                color: Appearance.m3colors.m3onSurface
                text: Duration.format10ms(stopwatchTab.ticks)
            }
            Digits {
                color: Appearance.colors.colSubtext
                text: "." + String(Math.floor(stopwatchTab.ticks) % 100).padStart(2, '0')
            }
        }

        StyledListView {
            id: lapsList
            anchors {
                top: elapsedIndicator.bottom
                bottom: controls.top
                left: parent.left
                right: parent.right
                topMargin: 16
                bottomMargin: 16
            }
            spacing: 4
            clip: true
            popin: true

            model: ScriptModel {
                values: TimerService.stopwatchLaps.map((v, i, arr) => arr[arr.length - 1 - i])
            }

            delegate: Rectangle {
                id: lapItem
                required property int index
                required property var modelData
                property var horizontalPadding: 12
                property var verticalPadding: 8
                width: lapsList.width
                implicitHeight: lapRow.implicitHeight + verticalPadding * 2
                implicitWidth: lapRow.implicitWidth + horizontalPadding * 2
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.small

                component LapText: StyledText {
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: ({})
                    font.features: ({ "tnum": 1 })
                }

                RowLayout {
                    id: lapRow
                    anchors {
                        fill: parent
                        leftMargin: lapItem.horizontalPadding
                        rightMargin: lapItem.horizontalPadding
                        topMargin: lapItem.verticalPadding
                        bottomMargin: lapItem.verticalPadding
                    }

                    LapText {
                        color: Appearance.colors.colSubtext
                        text: `${TimerService.stopwatchLaps.length - lapItem.index}.`
                    }

                    LapText {
                        text: Duration.format10ms(lapItem.modelData, true)
                    }

                    Item { Layout.fillWidth: true }

                    LapText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colPrimary
                        text: {
                            const originalIndex = TimerService.stopwatchLaps.length - lapItem.index - 1
                            const lastTime = originalIndex > 0 ? TimerService.stopwatchLaps[originalIndex - 1] : 0
                            const lap = Duration.format10ms(lapItem.modelData - lastTime, true)
                            return "+" + (lap.startsWith("00:") ? lap.slice(3) : lap)
                        }
                    }
                }
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
                iconName: TimerService.stopwatchRunning ? "flag" : "restart_alt"
                buttonText: TimerService.stopwatchRunning ? Translation.tr("Lap") : Translation.tr("Reset")
                enabled: TimerService.stopwatchRunning || TimerService.stopwatchTime > 0 || TimerService.stopwatchLaps.length > 0
                onClicked: {
                    if (TimerService.stopwatchRunning)
                        TimerService.stopwatchRecordLap();
                    else
                        TimerService.stopwatchReset();
                }
            }
            TimerButton {
                filled: true
                iconName: TimerService.stopwatchRunning ? "pause" : "play_arrow"
                buttonText: TimerService.stopwatchRunning ? Translation.tr("Pause") : TimerService.stopwatchTime === 0 ? Translation.tr("Start") : Translation.tr("Resume")
                buttonRadius: TimerService.stopwatchRunning ? Appearance.rounding.small : Math.min(Appearance.rounding.full, implicitHeight / 2)
                onClicked: TimerService.toggleStopwatch()
            }
        }
    }
}
