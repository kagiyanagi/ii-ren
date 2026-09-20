import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    title: Translation.tr("Calendar Upcoming 3 Days 1x1 Options")

    ContentSection {
        title: Translation.tr("Calendar Settings")
        icon: "calendar_month"

        Item {
            Layout.fillWidth: true
            implicitHeight: Appearance.sizes.pagePlaceholderHeight
            visible: !Config.isWidgetActive("calendar_upcoming_3days")

            PagePlaceholder {
                anchors.fill: parent
                icon: "event_busy"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Calendar Upcoming 3 Days 1x1 disabled")
                description: Translation.tr("Enable the Calendar Upcoming 3 Days 1x1 in Desktop Widgets settings to use this page.")
            }
        }

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
            visible: Config.isWidgetActive("calendar_upcoming_3days")
        }
    }
}
