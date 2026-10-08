import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("Circular media options")

    ContentSection {
        title: Translation.tr("Circular media settings")
        icon: "music_note"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("media_circular")

            PagePlaceholder {
                anchors.fill: parent
                icon: "music_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Circular media disabled")
                description: Translation.tr("Enable the Circular Media in Desktop Widgets settings to use this page.")
            }
        }

        ContentGroup {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("media_circular")

            ConfigSelectionRow {
                text: Translation.tr("Background shape")
                buttonIcon: "category"
                currentValue: Config.options.background.widgets.media.backgroundShape
                onSelected: newValue => {
                    Config.options.background.widgets.media.backgroundShape = newValue;
                }
                options: [
                    { displayName: Translation.tr("Circle"), icon: "circle", value: "circle" },
                    { displayName: Translation.tr("Square"), icon: "square", value: "square" },
                    { displayName: Translation.tr("Cookie"), icon: "cookie", value: "cookie" }
                ]
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Colors")
            }

            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Use album colors")
                checked: Config.options.background.widgets.media.useAlbumColors
                onCheckedChanged: {
                    Config.options.background.widgets.media.useAlbumColors = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "brush"
                text: Translation.tr("Tint art cover")
                checked: Config.options.background.widgets.media.tintArtCover
                onCheckedChanged: {
                    Config.options.background.widgets.media.tintArtCover = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Controls")
            }

            ConfigSwitch {
                buttonIcon: "visibility_off"
                text: Translation.tr("Hide all controls")
                checked: Config.options.background.widgets.media.hideAllButtons
                onCheckedChanged: {
                    Config.options.background.widgets.media.hideAllButtons = checked;
                }
            }

            ConfigSwitch {
                enabled: !Config.options.background.widgets.media.hideAllButtons
                buttonIcon: "skip_previous"
                text: Translation.tr("Show previous toggle")
                checked: Config.options.background.widgets.media.showPreviousToggle
                onCheckedChanged: {
                    Config.options.background.widgets.media.showPreviousToggle = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Glow")
            }

            ConfigSwitch {
                buttonIcon: "flare"
                text: Translation.tr("Enable glow")
                checked: Config.options.background.widgets.media.glow.enable
                onCheckedChanged: {
                    Config.options.background.widgets.media.glow.enable = checked;
                }
            }

            ConfigSpinBox {
                enabled: Config.options.background.widgets.media.glow.enable
                icon: "brightness_medium"
                text: Translation.tr("Brightness")
                value: Config.options.background.widgets.media.glow.brightness
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.background.widgets.media.glow.brightness = value;
                }
            }

            Item { Layout.preferredHeight: 4 }

            ContentSubsectionLabel {
                text: Translation.tr("Visualizer")
            }

            ConfigSwitch {
                buttonIcon: "graphic_eq"
                text: Translation.tr("Enable visualizer")
                checked: Config.options.background.widgets.media.visualizer.enable
                onCheckedChanged: {
                    Config.options.background.widgets.media.visualizer.enable = checked;
                }
            }

            ConfigSpinBox {
                enabled: Config.options.background.widgets.media.visualizer.enable
                icon: "opacity"
                text: Translation.tr("Opacity")
                value: Config.options.background.widgets.media.visualizer.opacity * 100
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.background.widgets.media.visualizer.opacity = value / 100;
                }
            }

            ConfigSpinBox {
                enabled: Config.options.background.widgets.media.visualizer.enable
                icon: "waves"
                text: Translation.tr("Smoothing")
                value: Config.options.background.widgets.media.visualizer.smoothing
                from: 1
                to: 20
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.media.visualizer.smoothing = value;
                }
            }

            ConfigSpinBox {
                enabled: Config.options.background.widgets.media.visualizer.enable
                icon: "blur_on"
                text: Translation.tr("Blur")
                value: Config.options.background.widgets.media.visualizer.blur
                from: 0
                to: 50
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.media.visualizer.blur = value;
                }
            }

            Item { Layout.preferredHeight: 4 }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
