pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.waffle.looks

WSessionScreenTextButton {
    id: root
    implicitWidth: 40
    implicitHeight: 40
    focusRingRadius: Looks.radius.large
    colBackground: ColorUtils.transparentize(Looks.darkColors.bg2)
    colBackgroundHover: Looks.applyContentTransparency(Looks.darkColors.bg2Hover)
    colBackgroundActive: Looks.applyContentTransparency(Looks.darkColors.bg2Active)
    property color color: {
        if (root.down) {
            return root.colBackgroundActive;
        } else if (root.hovered) {
            return root.colBackgroundHover;
        } else {
            return root.colBackground;
        }
    }
    background: Rectangle {
        id: background
        radius: Looks.radius.medium
        color: root.color
    }
    contentItem: Item {
        FluentIcon {
            anchors.centerIn: parent
            implicitSize: 20
            icon: "power"
            color: root.fgColor
        }
    }

    onClicked: {
        if (powerMenu.visible) {
            powerMenu.close();
        } else {
            powerMenu.open();
        }
    }

    function triggerAction(action) {
        if (GlobalStates.sessionOpen)
            GlobalStates.sessionOpen = false;
        action();
    }

    WMenu {
        id: powerMenu
        x: -powerMenu.implicitWidth / 2 + root.implicitWidth / 2
        y: -powerMenu.implicitHeight

        color: Looks.darkColors.bg1Base
        Component.onCompleted: {
            if (powerMenu.backgroundPane) {
                powerMenu.backgroundPane.borderColor = Looks.applyContentTransparency(Looks.darkColors.bg2Border);
            }
        }
        delegate: WMenuItem {
            id: menuItemDelegate
            colBackground: ColorUtils.transparentize(Looks.darkColors.bg1Base)
            colBackgroundHover: Looks.applyContentTransparency(Looks.darkColors.bg2Hover)
            colBackgroundActive: Looks.applyContentTransparency(Looks.darkColors.bg2Active)
            colForeground: Looks.darkColors.fg
        }

        Action {
            icon.name: "weather-moon"
            text: Translation.tr("Sleep")
            enabled: SessionWarnings.can("CanSuspend")
            onTriggered: root.triggerAction(() => Session.suspend())
        }
        Action {
            icon.name: "power"
            text: Translation.tr("Shut down")
            enabled: SessionWarnings.can("CanPowerOff")
            onTriggered: root.triggerAction(() => Session.poweroff())
        }
        Action {
            icon.name: "arrow-counterclockwise"
            text: Translation.tr("Restart")
            enabled: SessionWarnings.can("CanReboot")
            onTriggered: root.triggerAction(() => Session.reboot())
        }
    }
}
