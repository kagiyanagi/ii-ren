import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import "./cards"


Item {
    id: indicator
    property bool vertical: false

    property bool minimal: Config.options.bar.indicators.record.minimal
    property bool activelyRecording: Persistent.states.screenRecord.active

    // Customizable pill metrics (matching TimerWidget):
    property int pillHeight: 26        // Height of the capsule pill
    property int pillPadding: 10       // Horizontal padding on both outer ends
    property int iconSize: Appearance.font.pixelSize.normal // Icon size (16px)

    readonly property color colBackgroundNormal: Appearance.colors.colRecordChip
    readonly property color colBackgroundHover: Appearance.colors.colRecordChipHover
    readonly property color colBackgroundActive: Appearance.colors.colRecordChipActive
    readonly property color colBackground: button.down ? colBackgroundActive : button.hovered ? colBackgroundHover : colBackgroundNormal
    readonly property color colText: Appearance.colors.colOnRecordChip

    implicitWidth: pillContainer.implicitWidth
    implicitHeight: indicator.vertical ? pillContainer.implicitHeight : indicator.pillHeight

    Component.onCompleted: {
        if (typeof rootItem !== "undefined") {
            rootItem.isolated = true;
            rootItem.customHighlightColor = "transparent";
            rootItem.toggleHighlight(true);
        }
        updateVisibility();
    }

    onActivelyRecordingChanged: updateVisibility()

    function updateVisibility() {
        if (typeof rootItem !== "undefined") {
            rootItem.toggleVisible(activelyRecording);
        }
    }

    function formatTime(totalSeconds) {
        let hrs = Math.floor(totalSeconds / 3600);
        let mins = Math.floor((totalSeconds % 3600) / 60);
        let secs = totalSeconds % 60;
        if (hrs > 0) {
            return String(hrs).padStart(2, '0') + ":" + String(mins).padStart(2, '0') + ":" + String(secs).padStart(2, '0');
        }
        return String(mins).padStart(2, '0') + ":" + String(secs).padStart(2, '0');
    }

    Rectangle {
        id: pillContainer
        anchors.centerIn: parent
        height: indicator.vertical ? implicitHeight : indicator.pillHeight
        width: indicator.vertical ? indicator.pillHeight : implicitWidth
        implicitWidth: indicator.vertical ? indicator.pillHeight : (indicator.minimal ? (recordIcon.implicitWidth + indicator.pillPadding * 2) : (contentRow.implicitWidth + indicator.pillPadding * 2))
        implicitHeight: indicator.vertical ? (indicator.minimal ? (recordIconVert.implicitHeight + indicator.pillPadding * 2) : (contentCol.implicitHeight + indicator.pillPadding * 2)) : indicator.pillHeight
        radius: Appearance.rounding.full
        color: indicator.colBackground

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        RippleButton {
            id: button
            anchors.fill: parent
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: "transparent"
            colBackgroundActive: "transparent"
            colRipple: Qt.rgba(1, 1, 1, 0.25)
            
            onClicked: {
                Quickshell.execDetached([Directories.recordScriptPath, "--stop"])
            }
            StyledPopup {
                hoverTarget: button
                animate: false
                stickyHover: true // The action buttons need the popup to survive the pointer leaving the bar
                contentItem: PopupContent {}
            }
        }

        RowLayout {
            id: contentRow
            visible: !indicator.vertical
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                id: recordIcon
                text: "screen_record"
                fill: 1
                color: indicator.colText
                iconSize: indicator.iconSize
                horizontalAlignment: Text.AlignVCenter
                verticalAlignment: Text.AlignVCenter
            }

            StyledText {
                id: textIndicator
                visible: !indicator.minimal
                text: indicator.formatTime(Persistent.states.screenRecord.seconds)
                color: indicator.colText
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                font.family: Appearance.font.family.numbers
                font.features: ({ "tnum": 1 })
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        ColumnLayout {
            id: contentCol
            visible: indicator.vertical
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                id: recordIconVert
                text: "screen_record"
                fill: 1
                color: indicator.colText
                iconSize: indicator.iconSize
                Layout.alignment: Qt.AlignHCenter
            }

            StyledText {
                visible: !indicator.minimal
                text: indicator.formatTime(Persistent.states.screenRecord.seconds)
                color: indicator.colText
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                font.family: Appearance.font.family.numbers
                font.features: ({ "tnum": 1 })
                Layout.alignment: Qt.AlignHCenter
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
                onClicked: Quickshell.execDetached([Directories.recordScriptPath, "--stop"])
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
