pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack()

    RowLayout {
        spacing: Appearance.rounding.small

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: root.goBack()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        StyledText {
            text: Translation.tr("Cookie Clock Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "cookie"
        title: Translation.tr("Style & Shape")

        ConfigSpinBox {
            icon: "interests"
            text: Translation.tr("Sides")
            value: Config.options.background.widgets.clock_cookie.sides ?? 12
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
            checked: Config.options.background.widgets.clock_cookie.constantlyRotate ?? false
            onCheckedChanged: {
                Config.options.background.widgets.clock_cookie.constantlyRotate = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "more_horiz"
            text: Translation.tr("Hour marks")
            checked: Config.options.background.widgets.clock_cookie.hourMarks ?? true
            onCheckedChanged: {
                Config.options.background.widgets.clock_cookie.hourMarks = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "123"
            text: Translation.tr("Digits in the middle")
            checked: Config.options.background.widgets.clock_cookie.timeIndicators ?? true
            onCheckedChanged: {
                Config.options.background.widgets.clock_cookie.timeIndicators = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Background style")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock_cookie.backgroundStyle ?? "cookie"
                onSelected: newValue => {
                    Config.options.background.widgets.clock_cookie.backgroundStyle = String(newValue);
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
        }

        ContentSubsection {
            visible: Config.options.background.widgets.clock_cookie.backgroundStyle === "shape"
            title: Translation.tr("Background shape")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock_cookie.backgroundShape ?? "Cookie12Sided"
                onSelected: newValue => {
                    Config.options.background.widgets.clock_cookie.backgroundShape = String(newValue);
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
    }

    ContentSection {
        icon: "schedule"
        title: Translation.tr("Dial & Hands")

        ContentSubsection {
            title: Translation.tr("Dial style")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock_cookie.dialNumberStyle ?? "none"
                onSelected: newValue => {
                    Config.options.background.widgets.clock_cookie.dialNumberStyle = String(newValue);
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
        }

        ContentSubsection {
            title: Translation.tr("Hour hand")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock_cookie.hourHandStyle ?? "classic"
                onSelected: newValue => {
                    Config.options.background.widgets.clock_cookie.hourHandStyle = String(newValue);
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

        ContentSubsection {
            title: Translation.tr("Minute hand")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock_cookie.minuteHandStyle ?? "medium"
                onSelected: newValue => {
                    Config.options.background.widgets.clock_cookie.minuteHandStyle = String(newValue);
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

        ContentSubsection {
            title: Translation.tr("Second hand")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock_cookie.secondHandStyle ?? "line"
                onSelected: newValue => {
                    Config.options.background.widgets.clock_cookie.secondHandStyle = String(newValue);
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
        }

        ContentSubsection {
            title: Translation.tr("Date style")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock_cookie.dateStyle ?? "none"
                onSelected: newValue => {
                    Config.options.background.widgets.clock_cookie.dateStyle = String(newValue);
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
        }
    }

    ContentSection {
        icon: "auto_awesome"
        title: Translation.tr("AI Styling")

        ConfigSwitch {
            buttonIcon: "auto_awesome"
            text: Translation.tr("Auto style the cookie clock preset")
            checked: Config.options.background.widgets.clock_cookie.aiStyling ?? false
            onCheckedChanged: {
                Config.options.background.widgets.clock_cookie.aiStyling = checked;
            }
        }

        ContentSubsection {
            visible: Config.options.background.widgets.clock_cookie.aiStyling ?? false
            title: Translation.tr("AI model")

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock_cookie.aiStylingModel ?? "gemini"
                onSelected: newValue => {
                    Config.options.background.widgets.clock_cookie.aiStylingModel = String(newValue);
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
        }
    }

    ContentSection {
        icon: "format_quote"
        title: Translation.tr("Quote")

        ConfigSwitch {
            buttonIcon: "format_quote"
            text: Translation.tr("Enable quote")
            checked: Config.options.background.widgets.clock_cookie.quoteEnable ?? false
            onCheckedChanged: {
                Config.options.background.widgets.clock_cookie.quoteEnable = checked;
            }
        }

        ConfigTextField {
            enabled: Config.options.background.widgets.clock_cookie.quoteEnable ?? false
            icon: "edit"
            text: Translation.tr("Quote text")
            inputText: Config.options.background.widgets.clock_cookie.quoteText ?? ""
            onInputTextChanged: {
                Config.options.background.widgets.clock_cookie.quoteText = inputText;
            }
        }
    }

    ContentSection {
        visible: Config.isWidgetActive("clock_cookie")
        icon: "palette"
        title: Translation.tr("Visual Options")

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
        }
    }
}
