import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("Weather icon shape options")

    ContentSection {
        title: Translation.tr("Weather settings")
        icon: "cloud"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("weather_icon")

            PagePlaceholder {
                anchors.fill: parent
                icon: "cloud_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Weather icon shape disabled")
                description: Translation.tr("Enable the Weather Icon Shape in Desktop Widgets settings to use this page.")
            }
        }

        ContentGroup {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("weather_icon")

            ConfigSelectionRow {
                text: Translation.tr("Background shape")
                buttonIcon: "category"
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

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
