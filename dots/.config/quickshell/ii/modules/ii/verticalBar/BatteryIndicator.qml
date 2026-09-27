import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import qs.modules.ii.bar as Bar

// CustomBatteryMeter reads Battery itself; the five re-exports that sat here
// fed nothing, as in bar/BatteryIndicator.qml.
MouseArea {
    id: root

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
