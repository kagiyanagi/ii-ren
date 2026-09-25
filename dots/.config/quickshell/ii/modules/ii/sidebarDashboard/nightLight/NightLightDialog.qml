import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

WindowDialog {
    id: root

    // Comfort View and Reading Mode follow Night Light's times, so all three say
    // the same thing when automatic.
    function scheduleStatus(on, automatic) {
        if (automatic) return on ? Translation.tr("On until %1").arg(Hyprsunset.to) : Translation.tr("Turns on at %1").arg(Hyprsunset.from);
        return on ? Translation.tr("On") : Translation.tr("Off");
    }

    WindowDialogTitle {
        id: title
        text: Translation.tr("Eye protection")
    }

    // Scrolls only where the sidebar is too short for it; at 1080p it fits.
    StyledFlickable {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(body.implicitHeight, root.height - title.implicitHeight - buttonRow.implicitHeight - root.dialogPadding * 6)
        contentHeight: body.implicitHeight
        contentWidth: width
        clip: true

        ColumnLayout {
            id: body
            width: parent.width
            spacing: 12

            Card {
                SwitchRow {
                    first: true
                    title: Translation.tr("Night Light")
                    status: root.scheduleStatus(Hyprsunset.temperatureActive, Hyprsunset.automatic)
                    on: Hyprsunset.temperatureActive
                    onClicked: Hyprsunset.toggleTemperature(!Hyprsunset.temperatureActive)
                }
                // Right is warmer. hyprsunset retints live, so this one applies as it moves.
                EffectSlider {
                    from: 6500
                    to: 1200
                    stopIndicatorValues: [5000, to]
                    usePercentTooltip: false
                    tooltipContent: `${Math.round(value)}K`
                    value: Config.options.light.night.colorTemperature
                    onMoved: Config.options.light.night.colorTemperature = value
                }
                SwitchRow {
                    last: true
                    title: Translation.tr("Automatic")
                    on: Config.options.light.night.automatic
                    onClicked: Config.options.light.night.automatic = !Config.options.light.night.automatic
                }
            }

            Card {
                SwitchRow {
                    first: true
                    title: Translation.tr("Comfort View")
                    // The switch is the manual state; the schedule can have it on
                    // with the switch off, and the status line says so.
                    status: HyprlandComfortView.manualEnable ? Translation.tr("On") : root.scheduleStatus(HyprlandComfortView.effectiveActive, HyprlandComfortView.automatic)
                    on: HyprlandComfortView.manualEnable
                    onClicked: HyprlandComfortView.toggleManual()
                }
                EffectSlider {
                    value: HyprlandComfortView.intensity
                    onMoved: HyprlandComfortView.setIntensity(value)
                }
                SwitchRow {
                    last: true
                    title: Translation.tr("Automatic")
                    on: HyprlandComfortView.automatic
                    onClicked: HyprlandComfortView.toggleAutomatic()
                }
            }

            Card {
                SwitchRow {
                    first: true
                    title: Translation.tr("Reading Mode")
                    status: HyprlandReadingMode.manualEnable ? Translation.tr("On") : root.scheduleStatus(HyprlandReadingMode.effectiveActive, HyprlandReadingMode.automatic)
                    on: HyprlandReadingMode.manualEnable
                    onClicked: HyprlandReadingMode.toggleManual()
                }
                EffectSlider {
                    value: HyprlandReadingMode.intensity
                    onMoved: HyprlandReadingMode.setIntensity(value)
                }
                SwitchRow {
                    title: Translation.tr("Automatic")
                    on: HyprlandReadingMode.automatic
                    onClicked: HyprlandReadingMode.toggleAutomatic()
                }
                SwitchRow {
                    last: true
                    title: Translation.tr("Paper tone")
                    status: Translation.tr("Warms the grey like paper")
                    on: HyprlandReadingMode.paperTone
                    onClicked: HyprlandReadingMode.togglePaperTone()
                }
            }

            StyledText {
                Layout.topMargin: 4
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                text: Translation.tr("Anti-flashbang (experimental)")
            }

            Card {
                SwitchRow {
                    first: true
                    title: Translation.tr("Dim bright content")
                    status: Translation.tr("Instant, but costs GPU")
                    on: HyprlandAntiFlashbangShader.enabled
                    onClicked: HyprlandAntiFlashbangShader.toggle()
                }
                SwitchRow {
                    last: true
                    title: Translation.tr("Adapt screen brightness")
                    status: Translation.tr("Keeps colours, reacts slower")
                    on: Config.options.light.antiFlashbang.enable
                    onClicked: Config.options.light.antiFlashbang.enable = !Config.options.light.antiFlashbang.enable
                }
            }
        }
    }

    WindowDialogButtonRow {
        id: buttonRow

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }

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

    // The Wi-Fi and hotspot dialogs' switch row. The row owns the state and the
    // switch never toggles itself: ConfigSwitch's `checked = !checked` broke the
    // binding, and the binding's next update then called the service as if
    // clicked -- automatic Night Light turning on became a manual override.
    component SwitchRow: DialogListItem {
        id: row
        required property string title
        property string status
        property bool on
        property bool first
        property bool last
        Layout.fillWidth: true
        topLeftRadius: first ? Appearance.rounding.large : 0
        topRightRadius: topLeftRadius
        bottomLeftRadius: last ? Appearance.rounding.large : 0
        bottomRightRadius: bottomLeftRadius

        contentItem: RowLayout {
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colOnSurfaceVariant
                    elide: Text.ElideRight
                    text: row.title
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: row.status.length > 0
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    text: row.status
                }
            }
            StyledSwitch {
                checkable: false
                checked: row.on
                down: row.down
                focusPolicy: Qt.NoFocus
                onClicked: row.clicked()
            }
        }
    }

    component EffectSlider: StyledSlider {
        Layout.fillWidth: true
        Layout.leftMargin: 16
        Layout.rightMargin: 16
        Layout.bottomMargin: 8
        configuration: StyledSlider.Configuration.XS
        from: 0
        to: 100
    }
}
