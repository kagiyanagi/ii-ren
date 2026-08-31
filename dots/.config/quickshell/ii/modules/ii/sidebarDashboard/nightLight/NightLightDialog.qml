import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

WindowDialog {
    id: root
    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    backgroundHeight: 670

    WindowDialogTitle {
        text: Translation.tr("Eye protection")
    }

    StyledFlickable {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(scrollColumn.implicitHeight, 520)
        contentHeight: scrollColumn.implicitHeight
        contentWidth: width
        clip: true

        ColumnLayout {
            id: scrollColumn
            width: parent.width
            spacing: 12

            ContentSubsection {
                title: Translation.tr("Night Light")

                ConfigSwitch {
                    iconSize: Appearance.font.pixelSize.larger
                    buttonIcon: "check"
                    text: Translation.tr("Enable now")
                    checked: Hyprsunset.temperatureActive
                    onCheckedChanged: {
                        Hyprsunset.toggleTemperature(checked)
                    }
                }

                ConfigSwitch {
                    iconSize: Appearance.font.pixelSize.larger
                    buttonIcon: "night_sight_auto"
                    text: Translation.tr("Automatic")
                    checked: Config.options.light.night.automatic
                    onCheckedChanged: {
                        Config.options.light.night.automatic = checked;
                    }
                }

                ConfigSlider {
                    text: Translation.tr("Intensity")
                    from: 6500
                    to: 1200
                    stopIndicatorValues: [5000, to]
                    usePercentTooltip: false
                    value: Config.options.light.night.colorTemperature
                    onMoved: Config.options.light.night.colorTemperature = value
                    tooltipContent: `${Math.round(value)}K`
                }
            }

            ContentSubsection {
                title: Translation.tr("Comfort View")

                ConfigSwitch {
                    iconSize: Appearance.font.pixelSize.larger
                    buttonIcon: "visibility"
                    text: Translation.tr("Enable now")
                    checked: HyprlandComfortView.manualEnable
                    onCheckedChanged: {
                        HyprlandComfortView.toggleManual(checked);
                    }
                    StyledToolTip {
                        text: Translation.tr("Softens display colors and reduces OLED saturation to protect eyes.")
                    }
                }

                ConfigSwitch {
                    iconSize: Appearance.font.pixelSize.larger
                    buttonIcon: "auto_mode"
                    text: Translation.tr("Dynamic automatic")
                    checked: HyprlandComfortView.automatic
                    onCheckedChanged: {
                        HyprlandComfortView.toggleAutomatic(checked);
                    }
                    StyledToolTip {
                        text: Translation.tr("Automatically enables Comfort View based on schedule.")
                    }
                }

                ConfigSlider {
                    text: Translation.tr("Effect intensity")
                    from: 0
                    to: 100
                    value: HyprlandComfortView.intensity
                    onMoved: HyprlandComfortView.setIntensity(value)
                    tooltipContent: `${Math.round(value)}%`
                }
            }

            ContentSubsection {
                title: Translation.tr("Reading Mode")

                ConfigSwitch {
                    iconSize: Appearance.font.pixelSize.larger
                    buttonIcon: "menu_book"
                    text: Translation.tr("Enable now")
                    checked: HyprlandReadingMode.manualEnable
                    onCheckedChanged: {
                        HyprlandReadingMode.toggleManual(checked);
                    }
                    StyledToolTip {
                        text: Translation.tr("Grayscale monochrome display mode for long-term reading comfort.")
                    }
                }

                ConfigSwitch {
                    iconSize: Appearance.font.pixelSize.larger
                    buttonIcon: "auto_mode"
                    text: Translation.tr("Dynamic automatic")
                    checked: HyprlandReadingMode.automatic
                    onCheckedChanged: {
                        HyprlandReadingMode.toggleAutomatic(checked);
                    }
                    StyledToolTip {
                        text: Translation.tr("Automatically enables Reading Mode based on schedule.")
                    }
                }

                ConfigSwitch {
                    iconSize: Appearance.font.pixelSize.larger
                    buttonIcon: "history_edu"
                    text: Translation.tr("Paper warmth tone")
                    checked: HyprlandReadingMode.paperTone
                    onCheckedChanged: {
                        HyprlandReadingMode.togglePaperTone(checked);
                    }
                    StyledToolTip {
                        text: Translation.tr("Simulates natural paper reflection tone to further ease reading fatigue.")
                    }
                }

                ConfigSlider {
                    text: Translation.tr("Grayscale intensity")
                    from: 0
                    to: 100
                    value: HyprlandReadingMode.intensity
                    onMoved: HyprlandReadingMode.setIntensity(value)
                    tooltipContent: `${Math.round(value)}%`
                }
            }

            ContentSubsection {
                title: Translation.tr("Anti-flashbang (experimental)")

                ConfigSwitch {
                    iconSize: Appearance.font.pixelSize.larger
                    buttonIcon: "filter"
                    text: Translation.tr("Content adjustment")
                    checked: HyprlandAntiFlashbangShader.enabled
                    onCheckedChanged: {
                        if (checked) HyprlandAntiFlashbangShader.enable()
                        else HyprlandAntiFlashbangShader.disable()
                    }
                    StyledToolTip {
                        text: Translation.tr("<b>Dims screen content</b> as needed.<br><br>Pros: Immediately responsive<br>Cons: Expensive and can hurt color accuracy<br><br><i>Uses a Hyprland screen shader</i>")
                    }
                }

                ConfigSwitch {
                    iconSize: Appearance.font.pixelSize.larger
                    buttonIcon: "light_mode"
                    text: Translation.tr("Brightness adjustment")
                    checked: Config.options.light.antiFlashbang.enable
                    onCheckedChanged: {
                        Config.options.light.antiFlashbang.enable = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Adapts the <b>display (physical screen) brightness</b><br><br>Pros: Less expensive, retains colors<br>Cons: Not immediately responsive<br><br><i>Adjusts display brightness after each Hyprland IPC event</i>")
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Brightness")

                ConfigSlider {
                    value: root.brightnessMonitor.brightness
                    onMoved: root.brightnessMonitor.setBrightness(value)
                }
            }

            ContentSubsection {
                title: Translation.tr("Gamma")
                Layout.bottomMargin: 8

                ConfigSlider {
                    from: Hyprsunset.gammaLowerLimit / 100
                    value: Hyprsunset.gamma / 100
                    onMoved: Hyprsunset.setGamma(value * 100)
                    tooltipContent: `${Math.round(value * 100)}%`
                }
            }
        }
    }
    WindowDialogButtonRow {
        Layout.fillWidth: true

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
