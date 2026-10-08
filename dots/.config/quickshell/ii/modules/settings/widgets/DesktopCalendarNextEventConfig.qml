import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    title: Translation.tr("Calendar next event 2x1 options")

    ContentSection {
        title: Translation.tr("Calendar settings")
        icon: "calendar_month"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("calendar_next_event")

            PagePlaceholder {
                anchors.fill: parent
                icon: "event_busy"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Calendar next event 2x1 disabled")
                description: Translation.tr("Enable the Calendar Next Event 2x1 in Desktop Widgets settings to use this page.")
            }
        }

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("calendar_next_event")
        }
    }
}
