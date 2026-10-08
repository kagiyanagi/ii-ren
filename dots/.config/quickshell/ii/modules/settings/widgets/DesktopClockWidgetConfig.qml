import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("Cookie clock options")

    ContentSection {
        title: Translation.tr("Clock settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("clock_cookie")

            PagePlaceholder {
                anchors.fill: parent
                icon: "watch"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Cookie clock disabled")
                description: Translation.tr("Enable the Cookie Clock in Desktop Widgets settings to use this page.")
            }
        }

        ContentGroup {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("clock_cookie")

            // Cookie Style Settings
            ContentGroup {
                Layout.fillWidth: true

                ContentSubsectionLabel {
                    text: Translation.tr("Cookie style settings")
                }

                ConfigSpinBox {
                    icon: "interests"
                    text: Translation.tr("Sides")
                    value: Config.options.background.widgets.clock_cookie.sides
                    from: 3
                    to: 24
                    stepSize: 1
                    onValueChanged: {
                        Config.options.background.widgets.clock_cookie.sides = value;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "rotate_right"
                    text: Translation.tr("Constantly rotate")
                    checked: Config.options.background.widgets.clock_cookie.constantlyRotate
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_cookie.constantlyRotate = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "more_horiz"
                    text: Translation.tr("Hour marks")
                    checked: Config.options.background.widgets.clock_cookie.hourMarks
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_cookie.hourMarks = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "123"
                    text: Translation.tr("Digits in the middle")
                    checked: Config.options.background.widgets.clock_cookie.timeIndicators
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_cookie.timeIndicators = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "auto_awesome"
                    text: Translation.tr("Auto style the cookie clock preset")
                    checked: Config.options.background.widgets.clock_cookie.aiStyling
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_cookie.aiStyling = checked;
                    }
                }

                ConfigSelectionRow {
                    text: Translation.tr("AI model")
                    buttonIcon: "psychology"
                    visible: Config.options.background.widgets.clock_cookie.aiStyling
                    currentValue: Config.options.background.widgets.clock_cookie.aiStylingModel
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_cookie.aiStylingModel = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Gemini"),
                            icon: "smart_toy",
                            value: "gemini"
                        },
                        {
                            displayName: Translation.tr("ChatGPT"),
                            icon: "smart_toy",
                            value: "chatgpt"
                        },
                        {
                            displayName: Translation.tr("Claude"),
                            icon: "smart_toy",
                            value: "claude"
                        }
                    ]
                }

                ConfigSelectionRow {
                    text: Translation.tr("Dial style")
                    buttonIcon: "settings_overscan"
                    currentValue: Config.options.background.widgets.clock_cookie.dialNumberStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_cookie.dialNumberStyle = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("None"),
                            icon: "do_not_disturb",
                            value: "none"
                        },
                        {
                            displayName: Translation.tr("Dots"),
                            icon: "fiber_manual_record",
                            value: "dots"
                        },
                        {
                            displayName: Translation.tr("Shapes"),
                            icon: "category",
                            value: "shapes"
                        },
                        {
                            displayName: Translation.tr("Numbers"),
                            icon: "123",
                            value: "numbers"
                        },
                        {
                            displayName: Translation.tr("Lines"),
                            icon: "horizontal_rule",
                            value: "full"
                        }
                    ]
                }

                ConfigSelectionRow {
                    text: Translation.tr("Hour hand")
                    buttonIcon: "arrow_downward"
                    currentValue: Config.options.background.widgets.clock_cookie.hourHandStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_cookie.hourHandStyle = newValue;
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

                ConfigSelectionRow {
                    text: Translation.tr("Minute hand")
                    buttonIcon: "arrow_downward"
                    currentValue: Config.options.background.widgets.clock_cookie.minuteHandStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_cookie.minuteHandStyle = newValue;
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

                ConfigSelectionRow {
                    text: Translation.tr("Second hand")
                    buttonIcon: "arrow_downward"
                    currentValue: Config.options.background.widgets.clock_cookie.secondHandStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_cookie.secondHandStyle = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("None"),
                            icon: "do_not_disturb",
                            value: "hide"
                        },
                        {
                            displayName: Translation.tr("Line"),
                            icon: "horizontal_rule",
                            value: "line"
                        },
                        {
                            displayName: Translation.tr("Dot"),
                            icon: "fiber_manual_record",
                            value: "dot"
                        },
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "format_list_bulleted",
                            value: "classic"
                        }
                    ]
                }

                ConfigSelectionRow {
                    text: Translation.tr("Date style")
                    buttonIcon: "calendar_today"
                    currentValue: Config.options.background.widgets.clock_cookie.dateStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_cookie.dateStyle = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("None"),
                            icon: "do_not_disturb",
                            value: "hide"
                        },
                        {
                            displayName: Translation.tr("Bubble"),
                            icon: "bubble_chart",
                            value: "bubble"
                        },
                        {
                            displayName: Translation.tr("Rectangle"),
                            icon: "crop_square",
                            value: "rect"
                        },
                        {
                            displayName: Translation.tr("Border"),
                            icon: "border_style",
                            value: "border"
                        }
                    ]
                }

                ConfigSelectionRow {
                    text: Translation.tr("Background style")
                    buttonIcon: "wallpaper"
                    currentValue: Config.options.background.widgets.clock_cookie.backgroundStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_cookie.backgroundStyle = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Cookie"),
                            icon: "cookie",
                            value: "cookie"
                        },
                        {
                            displayName: Translation.tr("Sine"),
                            icon: "graphic_eq",
                            value: "sine"
                        },
                        {
                            displayName: Translation.tr("Shape"),
                            icon: "category",
                            value: "shape"
                        }
                    ]
                }

                ConfigSelectionRow {
                    text: Translation.tr("Background shape")
                    buttonIcon: "category"
                    visible: Config.options.background.widgets.clock_cookie.backgroundStyle === "shape"
                    currentValue: Config.options.background.widgets.clock_cookie.backgroundShape
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_cookie.backgroundShape = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Circle"),
                            icon: "circle",
                            value: "Circle"
                        },
                        {
                            displayName: Translation.tr("Square"),
                            icon: "square",
                            value: "Square"
                        },
                        {
                            displayName: Translation.tr("Cookie"),
                            icon: "cookie",
                            value: "Cookie12Sided"
                        }
                    ]
                }
            }

            Item {
                Layout.preferredHeight: 4
            }

            // Quote Settings
            ContentGroup {
                Layout.fillWidth: true

                ContentSubsectionLabel {
                    text: Translation.tr("Quote settings")
                }

                ConfigSwitch {
                    buttonIcon: "format_quote"
                    text: Translation.tr("Enable quote")
                    checked: Config.options.background.widgets.clock_cookie.quoteEnable
                    onCheckedChanged: {
                        Config.options.background.widgets.clock_cookie.quoteEnable = checked;
                    }
                }

                ConfigTextField {
                    enabled: Config.options.background.widgets.clock_cookie.quoteEnable
                    icon: "edit"
                    text: Translation.tr("Quote text")
                    inputText: Config.options.background.widgets.clock_cookie.quoteText
                    onInputTextChanged: {
                        Config.options.background.widgets.clock_cookie.quoteText = inputText;
                    }
                }
            }

            Item {
                Layout.preferredHeight: 4
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
