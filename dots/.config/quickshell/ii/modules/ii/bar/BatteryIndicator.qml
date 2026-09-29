import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

// CustomBatteryMeter reads the Battery singleton itself, so the five
// chargeState/isCharging/isPluggedIn/percentage/isLow re-exports that used to
// sit here fed nothing -- no file, including this one, read them.
MouseArea {
    id: root

    implicitWidth: batteryMeter.implicitWidth
    implicitHeight: Appearance.sizes.barHeight

    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    // A tap opens the whole story, as the resources widget opens the task manager.
    // With click-to-show popups the tap is the popup's.
    cursorShape: Qt.PointingHandCursor
    onClicked: {
        if (Config.options.bar.tooltips.clickToShow) return
        batteryPopup.close()
        Quickshell.execDetached(["env", "II_SETTINGS_PAGE=battery", "qs", "-p", Quickshell.shellPath("settings.qml")])
    }

    CustomBatteryMeter {
        id: batteryMeter
        anchors.centerIn: parent
    }

    BatteryPopup {
        id: batteryPopup
        hoverTarget: root
    }
}
