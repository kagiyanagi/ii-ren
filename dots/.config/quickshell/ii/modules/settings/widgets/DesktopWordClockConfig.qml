import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Word Clock Options")

    ContentSection {
        title: Translation.tr("Clock Settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("clock_word")

            PagePlaceholder {
                anchors.fill: parent
                icon: "watch"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Word Clock disabled")
                description: Translation.tr("Enable the Word Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("clock_word")

            ContentSubsectionLabel {
                text: Translation.tr("Size")
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Size")
                value: Config.options.background.widgets.clock_word.size
                from: 160
                to: 420
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.clock_word.size = Math.round(value);
                }
            }

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("Background style")
                icon: "wallpaper"

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock_word.backgroundStyle ?? "shape"
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_word.backgroundStyle = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Transparent"),
                            icon: "visibility_off",
                            value: "transparent"
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
                Layout.fillWidth: true
                visible: (Config.options.background.widgets.clock_word.backgroundStyle ?? "shape") === "shape"
                title: Translation.tr("Background shape")
                icon: "category"

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock_word.backgroundShape ?? "Circle"
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_word.backgroundShape = newValue;
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

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
