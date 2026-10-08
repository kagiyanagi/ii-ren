import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("WearOS clock (watch) options")

    ContentSection {
        title: Translation.tr("Clock settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("clock_wearos")

            PagePlaceholder {
                anchors.fill: parent
                icon: "watch"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("WearOS clock (watch) disabled")
                description: Translation.tr("Enable the WearOS Clock (Watch) in Desktop Widgets settings to use this page.")
            }
        }

        ContentGroup {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("clock_wearos")


            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget size (%)")
                value: Config.options.background.widgets.wearos_clock.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.wearos_clock.widgetSize = value;
                }
            }

            Item { Layout.preferredHeight: 4 }


            ConfigSwitch {
                buttonIcon: "schedule"
                text: Translation.tr("Show minute hand")
                checked: Config.options.background.widgets.wearos_clock.showMinuteHand ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showMinuteHand = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ── Dial Ring ──
            ContentSubsectionLabel {
                text: Translation.tr("Dial ring")
            }

            ConfigSwitch {
                buttonIcon: "circle"
                text: Translation.tr("Show bezel ring")
                checked: Config.options.background.widgets.wearos_clock.showBezelRing ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showBezelRing = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "pin"
                text: Translation.tr("Show outer numbers (00-58)")
                checked: Config.options.background.widgets.wearos_clock.showOuterNumbers ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showOuterNumbers = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "tag"
                text: Translation.tr("Show inner numbers (05-55)")
                checked: Config.options.background.widgets.wearos_clock.showInnerNumbers ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showInnerNumbers = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ── Complications ──
            ContentSubsectionLabel {
                text: Translation.tr("Complications")
            }

            ConfigSwitch {
                buttonIcon: "android"
                text: Translation.tr("Show distro logo")
                checked: Config.options.background.widgets.wearos_clock.showDistroLogo ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showDistroLogo = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Show sunset gauge")
                checked: Config.options.background.widgets.wearos_clock.showSunsetComplication ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showSunsetComplication = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "schedule"
                text: Translation.tr("Show digital time pill")
                checked: Config.options.background.widgets.wearos_clock.showDigitalTimePill ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showDigitalTimePill = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "battery_full"
                text: Translation.tr("Show battery pill")
                checked: Config.options.background.widgets.wearos_clock.showBatteryPill ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showBatteryPill = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "hourglass_bottom"
                text: Translation.tr("Show hour sub-dial")
                checked: Config.options.background.widgets.wearos_clock.showHourSubDial ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showHourSubDial = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "bedtime"
                text: Translation.tr("Show bedtime icon")
                checked: Config.options.background.widgets.wearos_clock.showBedtimeIcon ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showBedtimeIcon = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "phone_android"
                text: Translation.tr("Show KDE Connect status")
                checked: Config.options.background.widgets.wearos_clock.showKdeConnect ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showKdeConnect = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "calendar_today"
                text: Translation.tr("Show date complication")
                checked: Config.options.background.widgets.wearos_clock.showDateComplication ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showDateComplication = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ── Visual Options ──
            ContentSubsectionLabel {
                text: Translation.tr("Visual Options")
            }

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Enable glass reflection")
                checked: Config.options.background.widgets.wearos_clock.enableGlassReflection ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.enableGlassReflection = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Enable shadows")
                checked: Config.options.background.widgets.wearos_clock.enableShadows ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.enableShadows = checked;
                }
            }
        }
    }
}
