import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Date card options")

    ContentSection {
        title: Translation.tr("Date settings")
        icon: "calendar_today"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("date_default")

            PagePlaceholder {
                anchors.fill: parent
                icon: "calendar_today"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Date card disabled")
                description: Translation.tr("Enable the Date Card in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("date_default")

            DesktopWidgetVisualOptions {
                Layout.fillWidth: true
            }
        }
    }
}
