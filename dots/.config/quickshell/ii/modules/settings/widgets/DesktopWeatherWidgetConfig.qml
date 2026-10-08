import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    // One page for two registry entries — Default Weather and Expressive
    // Weather both point here, so it names both rather than a single widget.
    title: Translation.tr("Weather options")

    ContentSection {
        title: Translation.tr("Weather settings")
        icon: "cloud"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("weather_default") && !Config.isWidgetActive("weather_expressive")

            PagePlaceholder {
                anchors.fill: parent
                icon: "cloud_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Weather widgets disabled")
                description: Translation.tr("Enable the Default Weather or Expressive Weather in Desktop Widgets settings to use this page.")
            }
        }

        ContentGroup {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("weather_default") || Config.isWidgetActive("weather_expressive")

            ConfigSelectionRow {
                text: Translation.tr("Background shape")
                buttonIcon: "category"
                visible: Config.isWidgetActive("weather_expressive")
                currentValue: Config.options.background.widgets.weather.backgroundShape
                onSelected: newValue => {
                    Config.options.background.widgets.weather.backgroundShape = newValue;
                }
                options: ["Circle", "Pill", "Oval", "SemiCircle", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Puffy", "PuffyDiamond", "Bun", "SoftBurst", "Sunny", "VerySunny"].map(shape => {
                    return {
                        displayName: "",
                        shape: shape,
                        value: shape
                    };
                })
            }

            // Only the Expressive style has a shape to pick, so with just the
            // Default one on the group above is absent rather than disabled.
            ContentSubsectionLabel {
                visible: !Config.isWidgetActive("weather_expressive") && Config.isWidgetActive("weather_default")
                text: Translation.tr("No custom settings available for the Default style.")
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
