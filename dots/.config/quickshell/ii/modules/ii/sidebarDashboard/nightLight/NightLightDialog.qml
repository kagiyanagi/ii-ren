import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

WindowDialog {
    id: root

    // Each eye-protection tile opens its own dialog: "nightLight", "comfortView",
    // "readingMode" or "antiFlashbang". They used to share one that stacked all four.
    required property string effect

    readonly property bool active: ({
        nightLight: Hyprsunset.temperatureActive,
        comfortView: HyprlandComfortView.effectiveActive,
        readingMode: HyprlandReadingMode.effectiveActive,
        antiFlashbang: HyprlandAntiFlashbangShader.enabled || Config.options.light.antiFlashbang.enable
    })[effect]

    // Comfort View and Reading Mode follow Night Light's times, so all three say
    // the same thing when automatic.
    function scheduleStatus(on, automatic) {
        if (automatic) return on ? Translation.tr("On until %1").arg(Hyprsunset.to) : Translation.tr("Turns on at %1").arg(Hyprsunset.from);
        return on ? Translation.tr("On") : Translation.tr("Off");
    }

    // The Wi-Fi and audio dialogs' height: a share of the sidebar, so it scales with
    // the screen (about 600 at 1080p), and fixed while open. The body scrolls inside it.
    backgroundHeight: Math.round(root.height * 0.6)

    WindowDialogTitle {
        text: ({
            nightLight: Translation.tr("Night Light"),
            comfortView: Translation.tr("Comfort View"),
            readingMode: Translation.tr("Reading Mode"),
            antiFlashbang: Translation.tr("Anti-flashbang")
        })[root.effect]
    }

    StyledFlickable {
        id: flickable
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentHeight: body.height
        contentWidth: width
        clip: true

        // At least the card's height, so the controls sit on the Done row and the
        // spare height goes above them, to the icon.
        ColumnLayout {
            id: body
            width: parent.width
            height: Math.max(implicitHeight, flickable.height)
            spacing: 16

            // The tile's icon, large, centred in whatever height the controls
            // leave. On, it fills and morphs from a circle into a cookie, the way
            // an Android 16 tile's shape answers its state.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: hero.implicitHeight + 16

                MaterialShapeWrappedMaterialSymbol {
                    id: hero
                    property color tint: root.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                    anchors.centerIn: parent
                    padding: 24
                    iconSize: 48
                    shape: root.active ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                    color: root.active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHigh
                    colSymbol: hero.tint
                    fill: root.active ? 1 : 0
                    text: ({
                        nightLight: "bedtime",
                        comfortView: "visibility",
                        readingMode: "menu_book",
                        antiFlashbang: "flash_off"
                    })[root.effect]
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    Behavior on tint {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }

            DialogCard {
                visible: root.effect === "nightLight"
                SwitchRow {
                    first: true
                    title: Translation.tr("Use Night Light")
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
                    status: Translation.tr("%1 to %2").arg(Hyprsunset.from).arg(Hyprsunset.to)
                    on: Config.options.light.night.automatic
                    onClicked: Config.options.light.night.automatic = !Config.options.light.night.automatic
                }
            }

            DialogCard {
                visible: root.effect === "comfortView"
                SwitchRow {
                    first: true
                    title: Translation.tr("Use Comfort View")
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
                    status: Translation.tr("With Night Light, %1 to %2").arg(Hyprsunset.from).arg(Hyprsunset.to)
                    on: HyprlandComfortView.automatic
                    onClicked: HyprlandComfortView.toggleAutomatic()
                }
            }

            DialogCard {
                visible: root.effect === "readingMode"
                SwitchRow {
                    first: true
                    title: Translation.tr("Use Reading Mode")
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
                    status: Translation.tr("With Night Light, %1 to %2").arg(Hyprsunset.from).arg(Hyprsunset.to)
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

            DialogCard {
                visible: root.effect === "antiFlashbang"
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

            // What the effect is for, under the controls, like an Android
            // settings page's footer.
            WindowDialogParagraph {
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                color: Appearance.colors.colSubtext
                text: ({
                    nightLight: Translation.tr("Tints the screen amber. That is easier to look at in dim light, and may help you fall asleep."),
                    comfortView: Translation.tr("Softens and warms colour for long sessions. Reading Mode takes over while both are on."),
                    readingMode: Translation.tr("Turns the screen grey, like a page, so colour stops pulling at the eye while you read."),
                    antiFlashbang: Translation.tr("Experimental. Stops a sudden white screen from blinding you in the dark, by dimming it as it appears or by lowering the backlight to match.")
                })[root.effect]
            }
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
