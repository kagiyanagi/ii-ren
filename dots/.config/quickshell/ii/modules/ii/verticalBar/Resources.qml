import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import qs.modules.ii.bar as Bar

MouseArea {
    id: root
    // Nothing switched on leaves no padded empty slot behind.
    implicitHeight: columnLayout.implicitHeight > 0 ? columnLayout.implicitHeight + 16 : 0
    implicitWidth: columnLayout.implicitWidth
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    // Click-to-show owns the click for the popup.
    onClicked: if (!Config.options.bar.tooltips.clickToShow) Session.barClick("resources", Session.launchTaskManager)
    cursorShape: Qt.PointingHandCursor

    StateOverlay {
        anchors.centerIn: parent
        width: parent.width + 16
        height: parent.height
        radius: Appearance.rounding.full
        contentColor: Appearance.colors.colOnLayer1
        hover: root.containsMouse
        press: root.pressed
    }

    ColumnLayout {
        id: columnLayout
        spacing: 8
        anchors.centerIn: parent

        // bar/Resources.qml's order and switches. Temp, GPU and disk were
        // missing, so turning them on did nothing on a vertical bar.
        Resource {
            Layout.alignment: Qt.AlignHCenter
            iconName: "planner_review"
            percentage: ResourceUsage.cpuUsage
            shown: Config.options.bar.resources.showCpu ?? true
            warningThreshold: Config.options.bar.resources.cpuWarningThreshold ?? 90
        }

        Resource {
            Layout.alignment: Qt.AlignHCenter
            iconName: "memory"
            percentage: ResourceUsage.memoryUsedPercentage
            shown: Config.options.bar.resources.showRam ?? true
            warningThreshold: Config.options.bar.resources.memoryWarningThreshold ?? 95
        }

        Resource {
            Layout.alignment: Qt.AlignHCenter
            iconName: "thermostat"
            percentage: ResourceUsage.cpuTemp / 100
            shown: Config.options.bar.resources.showTemp ?? true
            warningThreshold: Config.options.bar.resources.tempWarningThreshold ?? 85
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
            iconName: "videogame_asset"
            percentage: ResourceUsage.gpuUsage
            shown: Config.options.bar.resources.showGpu ?? false
            warningThreshold: 90
        }

        Resource {
            Layout.alignment: Qt.AlignHCenter
            iconName: "hard_drive"
            percentage: ResourceUsage.diskUsedPercentage
            shown: Config.options.bar.resources.showDisk ?? false
            warningThreshold: 90
        }
    }

    Bar.ResourcesPopup {
        hoverTarget: root
    }
}
