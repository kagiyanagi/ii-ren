import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// CustomBatteryMeter reads the Battery singleton itself, so the five
// chargeState/isCharging/isPluggedIn/percentage/isLow re-exports that used to
// sit here fed nothing -- no file, including this one, read them.
MouseArea {
    id: root

    implicitWidth: batteryMeter.implicitWidth
    implicitHeight: Appearance.sizes.barHeight

    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    CustomBatteryMeter {
        id: batteryMeter
        anchors.centerIn: parent
    }

    BatteryPopup {
        id: batteryPopup
        hoverTarget: root
    }
}
