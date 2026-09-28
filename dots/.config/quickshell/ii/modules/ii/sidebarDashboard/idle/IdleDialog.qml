import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Android's Caffeine tile as the sidebar's other dialogs: the switch row the
// Wi-Fi and hotspot dialogs share, over a slider of durations.
WindowDialog {
    id: root
    // The sidebar dialogs' fixed height (TASTE 4.1).
    backgroundHeight: Math.round(root.height * 0.6)

    readonly property int picked: Persistent.states.idle.minutes ?? 0
    // minutes 0 is until turned off.
    readonly property var durations: [5, 10, 15, 30, 60, 120, 180, 360, 720, 1440, 0]

    function commit(): void {
        Idle.start(root.durations[Math.round(slider.value)]);
    }

    function label(m: int): string {
        return m === 0 ? Translation.tr("Always") : m < 60 ? `${m}m` : `${m / 60}h`;
    }

    readonly property string status: {
        if (!Idle.inhibit) return Translation.tr("Screen sleeps and locks as usual");
        if (Idle.until === 0) return Translation.tr("Awake until you turn it off");
        return Translation.tr("Awake until %1 · %2 left")
            .arg(Qt.formatTime(new Date(Idle.until), Config.options.time.format))
            .arg(Idle.remainingText);
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        WindowDialogTitle {
            text: Translation.tr("Keep awake")
        }
        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            text: root.status
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 12

        Card {
            DialogListItem {
                id: switchRow
                Layout.fillWidth: true
                buttonRadius: Appearance.rounding.large
                onClicked: Idle.toggleInhibit()

                contentItem: RowLayout {
                    spacing: 10
                    MaterialSymbol {
                        iconSize: Appearance.font.pixelSize.larger
                        text: Idle.inhibit ? "kettle" : "local_cafe"
                        color: Idle.inhibit ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            color: Appearance.colors.colOnSurfaceVariant
                            elide: Text.ElideRight
                            text: Translation.tr("Keep awake")
                        }
                        StyledText {
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                            // What the switch will do, since the tile's tap does the same.
                            text: root.picked === 0 ? Translation.tr("Until turned off")
                                : Translation.tr("For %1").arg(root.label(root.picked))
                        }
                    }
                    StyledSwitch {
                        checkable: false
                        checked: Idle.inhibit
                        down: switchRow.down
                        focusPolicy: Qt.NoFocus
                        onClicked: switchRow.clicked()
                    }
                }
            }
        }

        // The duration as one big readout over a stepped slider, like Android's
        // timer. It follows the drag and starts on release, so passing over 6h
        // on the way to 24h never starts a 6h one.
        Card {
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 16
                spacing: 8

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.huge * 2
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: ({})
                    font.features: ({ "tnum": 1 })
                    color: Idle.inhibit ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    text: root.label(root.durations[Math.round(slider.value)])
                }

                StyledSlider {
                    id: slider
                    Layout.fillWidth: true
                    configuration: StyledSlider.Configuration.M
                    from: 0
                    to: root.durations.length - 1
                    stepSize: 1
                    snapMode: Slider.SnapAlways
                    stopIndicatorValues: root.durations.map((_, i) => i)
                    showTooltip: false // the readout above is the value
                    value: root.durations.indexOf(root.picked)
                    onPressedChanged: if (!pressed) root.commit()
                    onMoved: if (!pressed) root.commit() // arrow keys
                }

                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: root.label(root.durations[0])
                    }
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: root.label(0)
                    }
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }

    WindowDialogButtonRow {
        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }

    // The DNS dialog's list card.
    component Card: Rectangle {
        default property alias rows: cardColumn.data
        Layout.fillWidth: true
        implicitHeight: cardColumn.implicitHeight
        radius: Appearance.rounding.large
        color: Appearance.colors.colSurfaceContainerHigh

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            spacing: 0
        }
    }
}
