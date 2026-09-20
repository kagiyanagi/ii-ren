import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Notes Widget Options")

    ContentSection {
        title: Translation.tr("Notes Widget Settings")
        icon: "note_stack"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("notes_widget") && !Config.isWidgetActive("notes_widget_2x1")

            PagePlaceholder {
                anchors.fill: parent
                icon: "note_stack"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Notes Widget disabled")
                description: Translation.tr("Enable the Notes Widget in Desktop Widgets settings to use this page.")
            }
        }

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("notes_widget") || Config.isWidgetActive("notes_widget_2x1")
        }
    }
}
