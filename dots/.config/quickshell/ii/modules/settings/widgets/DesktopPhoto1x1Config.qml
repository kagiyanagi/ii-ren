import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Photo 1x1 Widget Options")

    Process {
        id: pickImageProc
        command: ["bash", "-c", "if command -v kdialog &> /dev/null; then FILE=$(kdialog --getopenfilename \"$HOME\" \"*.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg *.PNG *.JPG *.JPEG *.GIF *.WEBP *.BMP *.SVG\" 2>/dev/null); elif command -v zenity &> /dev/null; then FILE=$(zenity --file-selection --file-filter=\"Images | *.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg *.PNG *.JPG *.JPEG *.GIF *.WEBP *.BMP *.SVG\" 2>/dev/null); fi; if [ -n \"$FILE\" ] && [ -f \"$FILE\" ]; then echo \"$FILE\"; fi"]
        stdout: SplitParser {
            onRead: data => {
                let path = data.trim();
                if (path.length > 0) {
                    Config.options.background.widgets.photo_1x1.imagePath = path;
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Photo 1x1 Widget Settings")
        icon: "image"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("photo_1x1")

            PagePlaceholder {
                anchors.fill: parent
                icon:    "image"
                shape:   MaterialShape.Shape.Circle
                title:       Translation.tr("Photo 1x1 Widget disabled")
                description: Translation.tr("Enable the Photo 1x1 Widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("photo_1x1")

            // ── Photo Selection ──────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Photo File") }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "folder_open"
                mainText: Translation.tr("Choose Image")
                onClicked: {
                    pickImageProc.running = false;
                    pickImageProc.running = true;
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: Config.options.background.widgets.photo_1x1.imagePath && Config.options.background.widgets.photo_1x1.imagePath !== ""
                text: Translation.tr("Current image: %1").arg(Config.options.background.widgets.photo_1x1.imagePath ?? "")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                visible: Config.options.background.widgets.photo_1x1.imagePath && Config.options.background.widgets.photo_1x1.imagePath !== ""
                materialIcon: "delete"
                mainText: Translation.tr("Remove Custom Image")
                onClicked: {
                    Config.options.background.widgets.photo_1x1.imagePath = "";
                }
            }

            // ── Material Shape Selection ─────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Material Shape") }

            ConfigSelectionArray {
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

            // ── Size ─────────────────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Size") }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text:  Translation.tr("Widget Size")
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
