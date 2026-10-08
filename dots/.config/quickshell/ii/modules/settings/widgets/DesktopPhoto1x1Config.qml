import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.utils

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("Photo 1x1 widget options")

    FilePickerProcess {
        id: pickImageProc
        label: "Images"
        patterns: ["*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.bmp", "*.svg", "*.PNG", "*.JPG", "*.JPEG", "*.GIF", "*.WEBP", "*.BMP", "*.SVG"]
        onPicked: path => Config.options.background.widgets.photo_1x1.imagePath = path
    }

    ContentSection {
        title: Translation.tr("Photo 1x1 widget settings")
        icon: "image"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("photo_1x1")

            PagePlaceholder {
                anchors.fill: parent
                icon:    "image"
                shape:   MaterialShape.Shape.Circle
                title:       Translation.tr("Photo 1x1 widget disabled")
                description: Translation.tr("Enable the Photo 1x1 Widget in Desktop Widgets settings to use this page.")
            }
        }

        ContentGroup {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("photo_1x1")

            // One card: the file in use as the summary, its two actions under it.
            ConfigLabeledRow {
                buttonIcon: "image"
                text: Translation.tr("Photo")
                summary: (Config.options.background.widgets.photo_1x1.imagePath ?? "") || Translation.tr("No photo chosen")

                RowLayout {
                    spacing: 4
                    RippleButtonWithIcon {
                        materialIcon: "folder_open"
                        mainText: Translation.tr("Choose image")
                        onClicked: pickImageProc.pick()
                    }
                    RippleButtonWithIcon {
                        visible: (Config.options.background.widgets.photo_1x1.imagePath ?? "").length > 0
                        materialIcon: "delete"
                        mainText: Translation.tr("Remove custom image")
                        onClicked: Config.options.background.widgets.photo_1x1.imagePath = ""
                    }
                }
            }

            // ── Material Shape Selection ─────────────────────────────────────
            ConfigSelectionRow {
                buttonIcon: "interests"
                text: Translation.tr("Shape")
                currentValue: Config.options.background.widgets.photo_1x1.backgroundShape ?? "Cookie9Sided"
                onSelected: value => Config.options.background.widgets.photo_1x1.backgroundShape = value
                options: ([
                    "Cookie9Sided", "Cookie12Sided", "Circle", "Rectangle", "Clover4Leaf", "Burst",
                    "Heart", "Bun", "Flower", "Puffy", "PuffyDiamond", "Sunny",
                    "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Ghostish",
                    "Clover8Leaf", "SoftBurst", "Boom", "SoftBoom", "Gem", "Diamond",
                    "Pentagon", "Square", "Arch", "Fan", "Arrow", "SemiCircle",
                    "Oval", "Pill", "Triangle", "Slanted", "ClamShell", "PixelCircle", "PixelTriangle"
                ]).map((shapeName) => {
                    return {
                        "displayName": "",
                        "shape": shapeName,
                        "value": shapeName
                    };
                })
            }


            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget size (%)")
                value: Config.options.background.widgets.photo_1x1.widgetSize ?? 100
                from: 50; to: 200; stepSize: 10
                onValueChanged: Config.options.background.widgets.photo_1x1.widgetSize = value
            }

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
