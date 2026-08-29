import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import "./cards"


MouseArea {
    id: indicator
    property bool vertical: false

    property bool minimal: Config.options.bar.indicators.record.minimal
    property bool activelyRecording: Persistent.states.screenRecord.active
    property color colText: Appearance.colors.colOnPrimary

    hoverEnabled: true
    implicitWidth: vertical ? 20 : minimal ? 50 : 80 // NOTE: Why do we have to enter a fixed size to make it dull?
    implicitHeight: vertical ? 50 : 20

    Component.onCompleted: {
        rootItem.toggleHighlight(true)
        updateVisibility()
    }
    onActivelyRecordingChanged: updateVisibility()

    function updateVisibility() {
        rootItem.toggleVisible(activelyRecording)
    }

    function formatTime(totalSeconds) {
        let mins = Math.floor(totalSeconds / 60);
        let secs = totalSeconds % 60;
        return String(mins).padStart(2, '0') + ":" + String(secs).padStart(2, '0');
    }

    RippleButton {
        anchors.centerIn: parent
        implicitWidth: indicator.vertical ? 20 : parent.implicitWidth
        implicitHeight: indicator.vertical ? parent.implicitHeight : 20
        colBackgroundHover: "transparent"
        colRipple: "transparent"
        
        onClicked: {
            Quickshell.execDetached(Directories.recordScriptPath)
        }
        StyledPopup {
            hoverTarget: indicator
            animate: false
            stickyHover: true // The action buttons need the popup to survive the pointer leaving the bar
            contentItem: PopupContent {}
        }
    }

    Loader {
        active: !indicator.vertical
        anchors.centerIn: parent
        sourceComponent: RowLayout {
            id: contentLayout
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                text: "screen_record"
                color: indicator.colText
                iconSize: Appearance.font.pixelSize.larger
                horizontalAlignment: Text.AlignVCenter
            }

            MaterialSymbol {
                text: "stop"
                fill: 1
                visible: minimal
                color: indicator.colText
                iconSize: Appearance.font.pixelSize.larger
                horizontalAlignment: Text.AlignVCenter
            }
            
            StyledText {
                id: textIndicator                
                Layout.topMargin: 2
                visible: !minimal

                text: indicator.formatTime(Persistent.states.screenRecord.seconds)
                color: indicator.colText
            }
        }
    }

    Loader {
        active: indicator.vertical
        anchors.centerIn: parent
        sourceComponent: ColumnLayout {
            id: contentLayout
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                Layout.topMargin: parent.spacing
                Layout.alignment: Text.AlignHCenter
                text: "screen_record"
                color: indicator.colText
                iconSize: Appearance.font.pixelSize.larger
                horizontalAlignment: Text.AlignHCenter
            }

            MaterialSymbol {
                Layout.alignment: Text.AlignHCenter
                text: "stop"
                fill: 1
                color: indicator.colText
                iconSize: Appearance.font.pixelSize.larger
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
    
    component PopupContent: ColumnLayout {
        spacing: 8

        HeroCard {
            Layout.fillWidth: true
            compactMode: true
            icon: "screen_record"

            title: Translation.tr("Recording...")
            subtitle: Persistent.states.screenRecord.paused ? Translation.tr("Paused") : Translation.tr("Click to stop recording")

            pillText: indicator.formatTime(Persistent.states.screenRecord.seconds)
            pillIcon: "timer"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 44
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                // ponytail: wf-recorder 0.6 has no pause, so this freezes it with SIGSTOP. The
                // paused span stays in the file as one held frame; cutting it needs a re-encode.
                onClicked: {
                    const paused = Persistent.states.screenRecord.paused;
                    Quickshell.execDetached(["pkill", paused ? "-CONT" : "-STOP", "wf-recorder"]);
                    Persistent.states.screenRecord.paused = !paused;
                }
                contentItem: Item {
                    implicitWidth: pauseRow.implicitWidth
                    implicitHeight: pauseRow.implicitHeight
                    RowLayout {
                        id: pauseRow
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: Persistent.states.screenRecord.paused ? "play_arrow" : "pause"
                            fill: 1
                            iconSize: 18
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: Persistent.states.screenRecord.paused ? Translation.tr("Resume") : Translation.tr("Pause")
                            color: Appearance.colors.colOnSecondaryContainer
                            font.pixelSize: Appearance.font.pixelSize.normal
                        }
                    }
                }
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 44
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colError
                colBackgroundHover: Appearance.colors.colErrorHover
                onClicked: Quickshell.execDetached([Directories.recordScriptPath])
                contentItem: Item {
                    implicitWidth: stopRow.implicitWidth
                    implicitHeight: stopRow.implicitHeight
                    RowLayout {
                        id: stopRow
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "stop"
                            fill: 1
                            iconSize: 18
                            color: Appearance.colors.colOnError
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: Translation.tr("Stop")
                            color: Appearance.colors.colOnError
                            font.pixelSize: Appearance.font.pixelSize.normal
                        }
                    }
                }
            }
        }
    }
    
}