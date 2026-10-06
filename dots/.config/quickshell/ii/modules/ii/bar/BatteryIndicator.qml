import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import Quickshell
import qs.services

// CustomBatteryMeter reads the Battery singleton itself, so the five
// chargeState/isCharging/isPluggedIn/percentage/isLow re-exports that used to
// sit here fed nothing -- no file, including this one, read them.
MouseArea {
    id: root

    // Material style: the level as text on a pill, a landscape battery on
    // the accent at its end (BarMaterialPill). This file is the horizontal bar's.
    readonly property bool material: Config.options.bar.barGroupStyle === 3
    implicitWidth: root.material ? (materialPill.item?.implicitWidth ?? 0) : batteryMeter.implicitWidth
    implicitHeight: Appearance.sizes.barHeight

    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    // A tap opens the whole story, as the resources widget opens the task manager.
    // With click-to-show popups the tap is the popup's.
    cursorShape: Qt.PointingHandCursor
    onClicked: {
        if (Config.options.bar.tooltips.clickToShow) return
        batteryPopup.close()
        Session.barClick("battery", () => Quickshell.execDetached(["env", "II_SETTINGS_PAGE=battery", "qs", "-p", Quickshell.shellPath("settings.qml")]))
    }

    CustomBatteryMeter {
        id: batteryMeter
        visible: !root.material
        anchors.centerIn: parent
    }

    Loader {
        id: materialPill
        active: root.material
        anchors.centerIn: parent
        sourceComponent: BarMaterialPill {
            id: pill
            accentFirst: false
            // Every battery setting still applies; a percentage the meter would
            // draw beside the icon becomes the pill's label instead.
            text: meter.displayOutsideText ? meter.percentageText : ""
            hover: root.containsMouse
            press: root.pressed

            // The meter's own colours are for the dark bar and vanish on the
            // light accent, so it takes the accent's: on-primary content over a
            // track between the two. The track stays opaque because the meter
            // draws its inside number in the track colour where it crosses the
            // fill. Error container is the red that contrasts with primary in
            // both light and dark schemes.
            CustomBatteryMeter {
                id: meter
                anchors.centerIn: parent
                drawOutsideText: false
                highlightColor: (isLow && !isCharging) ? Appearance.colors.colErrorContainer : Appearance.colors.colOnPrimary
                trackColor: (isCritical && !isCharging) ? Appearance.colors.colError : ColorUtils.mix(pill.colAccent, Appearance.colors.colOnPrimary, 0.7)
                contentColor: (isLow && !isCharging) ? Appearance.colors.colErrorContainer : Appearance.colors.colOnPrimary
            }
        }
    }

    BatteryPopup {
        id: batteryPopup
        hoverTarget: root
    }
}
