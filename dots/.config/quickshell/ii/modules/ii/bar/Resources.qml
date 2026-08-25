import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    implicitWidth: rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    RowLayout {
        id: rowLayout

        spacing: 0
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4

        Resource {
            iconName: "planner_review"
            percentage: ResourceUsage.cpuUsage
            shown: true
            warningThreshold: Config.options.bar.resources.cpuWarningThreshold
        }

        Resource {
            iconName: "memory"
            percentage: ResourceUsage.memoryUsedPercentage
            shown: true
            Layout.leftMargin: shown ? 6 : 0
            warningThreshold: Config.options.bar.resources.memoryWarningThreshold
        }

        Resource {
            iconName: "thermostat"
            // The ring is a 0-100 scale and Resource renders the label as
            // percentage * 100, so dividing by 100 puts degrees C straight on
            // both. Celsius only - Fahrenheit does not fit a 0-100 ring.
            percentage: ResourceUsage.cpuTemp / 100
            shown: true
            Layout.leftMargin: shown ? 6 : 0
            // Degrees, not percent, for the same reason.
            warningThreshold: 85
        }

    }

    ResourcesPopup {
        hoverTarget: root
    }
}
