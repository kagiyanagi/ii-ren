import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Month clock options")

    ContentSection {
        title: Translation.tr("Clock settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("month_clock")

            PagePlaceholder {
                anchors.fill: parent
                icon: "watch"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Month clock disabled")
                description: Translation.tr("Enable the Month Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("month_clock")

            // ── Size ─────────────────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Size") }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text:  Translation.tr("Widget size")
                value: Config.options.background.widgets.month_clock.widgetSize ?? 100
                from: 50; to: 200; stepSize: 10
                onValueChanged: Config.options.background.widgets.month_clock.widgetSize = value
            }

            // ── Rings ─────────────────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Rings") }

            ConfigSwitch {
                buttonIcon: "calendar_today"
                text:    Translation.tr("Month ring")
                checked: Config.options.background.widgets.month_clock.showMonthRing ?? true
                onCheckedChanged: Config.options.background.widgets.month_clock.showMonthRing = checked
            }
            ConfigSwitch {
                buttonIcon: "event"
                text:    Translation.tr("Day ring")
                checked: Config.options.background.widgets.month_clock.showDayRing ?? true
                onCheckedChanged: Config.options.background.widgets.month_clock.showDayRing = checked
            }
            ConfigSwitch {
                buttonIcon: "date_range"
                text:    Translation.tr("Weekday ring")
                checked: Config.options.background.widgets.month_clock.showWeekRing ?? true
                onCheckedChanged: Config.options.background.widgets.month_clock.showWeekRing = checked
            }

            // ── Pill indicators ───────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Pill indicators") }

            ConfigSwitch {
                buttonIcon: "label"
                text:    Translation.tr("Month pill")
                checked: Config.options.background.widgets.month_clock.showMonthPill ?? true
                onCheckedChanged: Config.options.background.widgets.month_clock.showMonthPill = checked
            }
            ConfigSwitch {
                buttonIcon: "label"
                text:    Translation.tr("Day pill")
                checked: Config.options.background.widgets.month_clock.showDayPill ?? true
                onCheckedChanged: Config.options.background.widgets.month_clock.showDayPill = checked
            }
            ConfigSwitch {
                buttonIcon: "label"
                text:    Translation.tr("Weekday pill")
                checked: Config.options.background.widgets.month_clock.showWeekPill ?? true
                onCheckedChanged: Config.options.background.widgets.month_clock.showWeekPill = checked
            }

            // ── Analog Hands ──────────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Analog hands") }

            ContentSubsection {
                title: Translation.tr("Hour hand style")
                icon: "schedule"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.month_clock.hourHandStyle ?? "fill"
                    onSelected: newValue => {
                        Config.options.background.widgets.month_clock.hourHandStyle = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Fill"), icon: "crop_square", value: "fill" },
                        { displayName: Translation.tr("Hollow"), icon: "crop_square", value: "hollow" },
                        { displayName: Translation.tr("Classic"), icon: "format_list_bulleted", value: "classic" },
                        { displayName: Translation.tr("Hide"), icon: "visibility_off", value: "hide" }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Minute hand style")
                icon: "schedule"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.month_clock.minuteHandStyle ?? "medium"
                    onSelected: newValue => {
                        Config.options.background.widgets.month_clock.minuteHandStyle = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Thin"), icon: "horizontal_rule", value: "thin" },
                        { displayName: Translation.tr("Medium"), icon: "remove", value: "medium" },
                        { displayName: Translation.tr("Bold"), icon: "add", value: "bold" },
                        { displayName: Translation.tr("Classic"), icon: "format_list_bulleted", value: "classic" },
                        { displayName: Translation.tr("Hide"), icon: "visibility_off", value: "hide" }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Second hand style")
                icon: "schedule"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.month_clock.secondHandStyle ?? "line"
                    onSelected: newValue => {
                        Config.options.background.widgets.month_clock.secondHandStyle = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Line"), icon: "remove", value: "line" },
                        { displayName: Translation.tr("Dot"), icon: "circle", value: "dot" },
                        { displayName: Translation.tr("Classic"), icon: "format_list_bulleted", value: "classic" },
                        { displayName: Translation.tr("Hide"), icon: "visibility_off", value: "hide" }
                    ]
                }
            }

            // ── Style ─────────────────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Style & appearance") }

            ConfigSwitch {
                buttonIcon: "density_medium"
                text:    Translation.tr("Show tick marks")
                checked: Config.options.background.widgets.month_clock.showTickMarks ?? true
                onCheckedChanged: Config.options.background.widgets.month_clock.showTickMarks = checked
            }
            ConfigSwitch {
                buttonIcon: "format_bold"
                text:    Translation.tr("Bold font")
                checked: Config.options.background.widgets.month_clock.boldFont ?? true
                onCheckedChanged: Config.options.background.widgets.month_clock.boldFont = checked
            }
            ConfigSwitch {
                buttonIcon: "contrast"
                text:    Translation.tr("Black background")
                checked: Config.options.background.widgets.month_clock.useBlackBg ?? true
                onCheckedChanged: Config.options.background.widgets.month_clock.useBlackBg = checked
            }
            ConfigSwitch {
                buttonIcon: "wb_twilight"
                text:    Translation.tr("Glass reflection")
                checked: Config.options.background.widgets.month_clock.enableGlassReflection ?? false
                onCheckedChanged: Config.options.background.widgets.month_clock.enableGlassReflection = checked
            }
        }
    }
}
