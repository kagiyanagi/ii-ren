import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Dial clock options")

    ContentSection {
        title: Translation.tr("Clock settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("clock_dial")

            PagePlaceholder {
                anchors.fill: parent
                icon: "watch"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Dial clock disabled")
                description: Translation.tr("Enable the Dial Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("clock_dial")

            // ── Hour Hand Style ──
            ContentSubsection {
                title: Translation.tr("Hour hand")
                icon: "arrow_upward"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock_dial.hourHandStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_dial.hourHandStyle = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "horizontal_rule",
                            value: "classic"
                        },
                        {
                            displayName: Translation.tr("Fill"),
                            icon: "square",
                            value: "fill"
                        },
                        {
                            displayName: Translation.tr("Hollow"),
                            icon: "crop_square",
                            value: "hollow"
                        },
                        {
                            displayName: Translation.tr("Hide"),
                            icon: "do_not_disturb",
                            value: "hide"
                        }
                    ]
                }
            }

            // ── Minute Hand Style ──
            ContentSubsection {
                title: Translation.tr("Minute hand")
                icon: "arrow_downward"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock_dial.minuteHandStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_dial.minuteHandStyle = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Thin"),
                            icon: "horizontal_rule",
                            value: "thin"
                        },
                        {
                            displayName: Translation.tr("Medium"),
                            icon: "remove",
                            value: "medium"
                        },
                        {
                            displayName: Translation.tr("Bold"),
                            icon: "add",
                            value: "bold"
                        },
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "format_list_bulleted",
                            value: "classic"
                        },
                        {
                            displayName: Translation.tr("Hide"),
                            icon: "do_not_disturb",
                            value: "hide"
                        }
                    ]
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ── Other Hands ──
            ContentSubsectionLabel {
                text: Translation.tr("Other hands")
            }

            ConfigSwitch {
                buttonIcon: "schedule"
                text: Translation.tr("Show minute hand")
                checked: Config.options.background.widgets.clock_dial.showMinuteHand ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.clock_dial.showMinuteHand = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "timer"
                text: Translation.tr("Show second hand")
                checked: Config.options.background.widgets.clock_dial.showSecondHand ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.clock_dial.showSecondHand = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ── Dial Elements ──
            ContentSubsectionLabel {
                text: Translation.tr("Dial elements")
            }

            ConfigSwitch {
                buttonIcon: "reorder"
                text: Translation.tr("Show dial ticks")
                checked: Config.options.background.widgets.clock_dial.showTicks ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.clock_dial.showTicks = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "pin"
                text: Translation.tr("Show number ring (12, 3, 6, 9)")
                checked: Config.options.background.widgets.clock_dial.showNumberRing ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.clock_dial.showNumberRing = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ── Visual Options ──
            ContentSubsectionLabel {
                text: Translation.tr("Visual Options")
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Enable shadows")
                checked: Config.options.background.widgets.clock_dial.enableShadows ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.clock_dial.enableShadows = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Enable inner shadow")
                checked: Config.options.background.widgets.clock_dial.enableInnerShadow ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.clock_dial.enableInnerShadow = checked;
                }
            }
        }
    }
}
