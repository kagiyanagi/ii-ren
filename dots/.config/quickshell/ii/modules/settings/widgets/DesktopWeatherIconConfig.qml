import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Weather Icon Shape Options")

    ContentSection {
        title: Translation.tr("Weather Settings")
        icon: "cloud"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("weather_icon")

            PagePlaceholder {
                anchors.fill: parent
                icon: "cloud_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Weather Icon Shape disabled")
                description: Translation.tr("Enable the Weather Icon Shape in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            visible: Config.isWidgetActive("weather_icon")

            ContentSubsection {
                Layout.fillWidth: true
                title: Translation.tr("Background shape")
                icon: "category"

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.weather_icon.backgroundShape ?? "Cookie12Sided"
                    onSelected: newValue => {
                        Config.options.background.widgets.weather_icon.backgroundShape = newValue;
                    }
                    options: ["Circle", "Pill", "Oval", "SemiCircle", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Puffy", "PuffyDiamond", "Bun", "SoftBurst", "Sunny", "VerySunny"].map(shape => {
                        return {
                            displayName: "",
                            shape: shape,
                            value: shape
                        };
                    })
                }
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
