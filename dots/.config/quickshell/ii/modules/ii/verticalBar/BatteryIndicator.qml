import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import Quickshell
import qs.modules.ii.bar as Bar

// CustomBatteryMeter reads Battery itself; the five re-exports that sat here
// fed nothing, as in bar/BatteryIndicator.qml.
MouseArea {
    id: root

    implicitWidth: batteryMeter.implicitWidth
    implicitHeight: batteryMeter.implicitHeight
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
        vertical: true
    }

    Bar.BatteryPopup {
        id: batteryPopup
        hoverTarget: root
    }
}
