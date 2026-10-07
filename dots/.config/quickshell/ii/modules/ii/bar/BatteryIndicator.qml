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
        Quickshell.execDetached(["env", "II_SETTINGS_PAGE=battery", "qs", "-p", Quickshell.shellPath("settings.qml")])
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

            // Every style is sized for the bare bar, ~18-20px tall, which left
            // a 3px rim of accent round it. Scaled to leave 4 all round, the
            // inset the accent keeps from its pill. Text-only stays full size,
            // like the clock's time.
            Item {
                readonly property real fit: meter.style === "text" ? 1 : Math.min(1, (pill.height - 16) / meter.implicitHeight)
                anchors.centerIn: parent
                implicitWidth: meter.implicitWidth * fit
                implicitHeight: meter.implicitHeight * fit

                // The meter's own track is secondary container, the accent's
                // tone, so it would vanish: the track is the accent's on-colour
                // at 28% instead, mixed in rather than translucent because the
                // meter draws its inside number in the track colour where it
                // crosses the fill. The low and critical reds are the meter's own.
                CustomBatteryMeter {
                    id: meter
                    anchors.centerIn: parent
                    scale: parent.fit
                    drawOutsideText: false
                    highlightColor: (isLow && !isCharging) ? Appearance.colors.colError : Appearance.colors.colOnPrimaryContainer
                    trackColor: (isCritical && !isCharging) ? Appearance.colors.colErrorContainer : ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, pill.colAccent, 0.28)
                    contentColor: (isLow && !isCharging) ? Appearance.colors.colError : Appearance.colors.colOnPrimaryContainer
                }
            }
        }
    }

    BatteryPopup {
        id: batteryPopup
        hoverTarget: root
    }
}
