import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.ii.bar as Bar

MouseArea {
    id: root
    readonly property var chargeState: Battery.chargeState
    readonly property bool isCharging: Battery.isCharging
    readonly property bool isPluggedIn: Battery.isPluggedIn
    readonly property real percentage: Battery.percentage
    readonly property bool isLow: percentage <= Config.options.battery.low / 100

    implicitWidth: batteryMeter.implicitWidth
    implicitHeight: batteryMeter.implicitHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    CustomBatteryMeter {
        id: batteryMeter
        anchors.centerIn: parent
        vertical: true
    }

    Bar.BatteryPopup {
        id: batteryPopup
        hoverTarget: root
    }
}
