import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("Word clock options")

    ContentSection {
        title: Translation.tr("Clock settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("clock_word")

            PagePlaceholder {
                anchors.fill: parent
                icon: "watch"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Word clock disabled")
                description: Translation.tr("Enable the Word Clock in Desktop Widgets settings to use this page.")
            }
        }

        ContentGroup {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("clock_word")

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget size (px)")
                value: Config.options.background.widgets.clock_word.size
                from: 160
                to: 420
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.clock_word.size = Math.round(value);
                }
            }

            ConfigSelectionRow {
                text: Translation.tr("Background style")
                buttonIcon: "wallpaper"
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

            ConfigSelectionRow {
                text: Translation.tr("Background shape")
                buttonIcon: "category"
                visible: (Config.options.background.widgets.clock_word.backgroundStyle ?? "shape") === "shape"
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

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
