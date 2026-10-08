import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("WearOS arc clock options")

    ContentSection {
        title: Translation.tr("Clock settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("wearos_arc_clock")

            PagePlaceholder {
                anchors.fill: parent
                icon: "watch"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("WearOS arc clock disabled")
                description: Translation.tr("Enable the WearOS Arc Clock in Desktop Widgets settings to use this page.")
            }
        }

        ContentGroup {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("wearos_arc_clock")


            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget size (%)")
                value: Config.options.background.widgets.wearos_arc_clock.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.wearos_arc_clock.widgetSize = value;
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ── Appearance Toggles ──
            ContentSubsectionLabel {
                text: Translation.tr("Appearance")
            }

            ConfigSwitch {
                buttonIcon: "dark_mode"
                text: Translation.tr("AMOLED black background")
                checked: Config.options.background.widgets.wearos_arc_clock.blackBackground ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_arc_clock.blackBackground = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "lens"
                text: Translation.tr("Enable glass reflection")
                checked: Config.options.background.widgets.wearos_arc_clock.enableGlassReflection ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_arc_clock.enableGlassReflection = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "grid_on"
                text: Translation.tr("Enable background dotted pattern")
                checked: Config.options.background.widgets.wearos_arc_clock.enableBackgroundPattern ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_arc_clock.enableBackgroundPattern = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "content_copy"
                text: Translation.tr("Enable shadows")
                checked: Config.options.background.widgets.wearos_arc_clock.enableShadows ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_arc_clock.enableShadows = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ── Complications ──
            ContentSubsectionLabel {
                text: Translation.tr("Complications")
            }

            // Left Complication selection
            ConfigLabeledRow {
                text: Translation.tr("Left complication")
                buttonIcon: "west"
                StyledComboBox {
                    buttonIcon: "star"
                    textRole: "displayName"
                    model: [
                        { displayName: Translation.tr("Weather info"), value: "weather" },
                        { displayName: Translation.tr("Laptop battery"), value: "battery" },
                        { displayName: Translation.tr("KdeConnect phone battery"), value: "phone_battery" },
                        { displayName: Translation.tr("Bluetooth battery"), value: "bluetooth_battery" },
                        { displayName: Translation.tr("Water drink counter"), value: "water_reminder" },
                        { displayName: Translation.tr("CPU Usage"), value: "cpu_usage" },
                        { displayName: Translation.tr("RAM memory usage"), value: "memory_usage" },
                        { displayName: Translation.tr("None"), value: "none" }
                    ]
                    currentIndex: {
                        const activeVal = Config.options.background.widgets.wearos_arc_clock.leftComplication ?? "weather";
                        const idx = model.findIndex(item => item.value === activeVal);
                        return idx !== -1 ? idx : 0;
                    }
                    onActivated: index => {
                        Config.options.background.widgets.wearos_arc_clock.leftComplication = model[index].value;
                    }
                }
            }

            // Right Complication selection
            ConfigLabeledRow {
                text: Translation.tr("Right complication")
                buttonIcon: "east"
                StyledComboBox {
                    buttonIcon: "star"
                    textRole: "displayName"
                    model: [
                        { displayName: Translation.tr("Weather info"), value: "weather" },
                        { displayName: Translation.tr("Laptop battery"), value: "battery" },
                        { displayName: Translation.tr("KdeConnect phone battery"), value: "phone_battery" },
                        { displayName: Translation.tr("Bluetooth battery"), value: "bluetooth_battery" },
                        { displayName: Translation.tr("Water drink counter"), value: "water_reminder" },
                        { displayName: Translation.tr("CPU Usage"), value: "cpu_usage" },
                        { displayName: Translation.tr("RAM memory usage"), value: "memory_usage" },
                        { displayName: Translation.tr("None"), value: "none" }
                    ]
                    currentIndex: {
                        const activeVal = Config.options.background.widgets.wearos_arc_clock.rightComplication ?? "battery";
                        const idx = model.findIndex(item => item.value === activeVal);
                        return idx !== -1 ? idx : 0;
                    }
                    onActivated: index => {
                        Config.options.background.widgets.wearos_arc_clock.rightComplication = model[index].value;
                    }
                }
            }

            // Bottom Complication selection
            ConfigLabeledRow {
                text: Translation.tr("Bottom complication")
                buttonIcon: "south"
                StyledComboBox {
                    buttonIcon: "title"
                    textRole: "displayName"
                    model: [
                        { displayName: Translation.tr("Calendar next event"), value: "calendar" },
                        { displayName: Translation.tr("Next to-do"), value: "todo" },
                        { displayName: Translation.tr("Active media status"), value: "media" },
                        { displayName: Translation.tr("Water reminder goal"), value: "water" },
                        { displayName: Translation.tr("None"), value: "none" }
                    ]
                    currentIndex: {
                        const activeVal = Config.options.background.widgets.wearos_arc_clock.bottomComplication ?? "calendar";
                        const idx = model.findIndex(item => item.value === activeVal);
                        return idx !== -1 ? idx : 0;
                    }
                    onActivated: index => {
                        Config.options.background.widgets.wearos_arc_clock.bottomComplication = model[index].value;
                    }
                }
            }
        }
    }
}
