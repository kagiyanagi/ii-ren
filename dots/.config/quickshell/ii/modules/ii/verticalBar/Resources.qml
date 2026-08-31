import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import qs.modules.ii.bar as Bar

MouseArea {
    id: root
    implicitHeight: columnLayout.implicitHeight + 15
    implicitWidth: columnLayout.implicitWidth
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    ColumnLayout {
        id: columnLayout
        spacing: 10
        anchors.centerIn: parent

        Resource {
            Layout.alignment: Qt.AlignHCenter
            iconName: "memory"
            percentage: ResourceUsage.memoryUsedPercentage
            shown: Config.options.bar.resources.showRam ?? true
            warningThreshold: Config.options.bar.resources.memoryWarningThreshold ?? 95
        }

        Resource {
            Layout.alignment: Qt.AlignHCenter
            iconName: "swap_horiz"
            percentage: ResourceUsage.swapUsedPercentage
            shown: Config.options.bar.resources.showSwap ?? false
            warningThreshold: Config.options.bar.resources.swapWarningThreshold ?? 85
        }

        Resource {
            Layout.alignment: Qt.AlignHCenter
            iconName: "planner_review"
            percentage: ResourceUsage.cpuUsage
            shown: Config.options.bar.resources.showCpu ?? true
            warningThreshold: Config.options.bar.resources.cpuWarningThreshold ?? 90
        }

    }

    Bar.ResourcesPopup {
        hoverTarget: root
    }
}
