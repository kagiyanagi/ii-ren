pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks
import "window-layout.js" as WindowLayout

WMouseAreaButton {
    id: root

    required property var toplevel
    required property int maxHeight
    required property int maxWidth

    property var hyprlandClient: HyprlandData.clientForToplevel(root.toplevel)
    property string address: hyprlandClient?.address ?? ""

    property string iconName: AppSearch.guessIcon(hyprlandClient?.class)

    color: root.Drag.active ? ColorUtils.transparentize(Looks.colors.bg1Base) : (containsMouse ? Looks.colors.bg1Base : Looks.colors.bgPanelFooterBackground)
    borderColor: ColorUtils.transparentize(Looks.colors.bg2Border, root.Drag.active ? 1 : 0)
    radius: Looks.radius.xLarge

    property real titleBarImplicitHeight: titleBar.implicitHeight
    property bool scaleSize: true
    property size openedSize: WindowLayout.scaleWindow(hyprlandClient, maxWidth, maxHeight)
    property size fullSize: Qt.size(hyprlandClient?.size?.[0] ?? maxWidth, hyprlandClient?.size?.[1] ?? maxHeight)
    property size size: scaleSize ? openedSize : fullSize
    implicitWidth: Math.max(Math.round(contentItem.implicitWidth), 140)
    implicitHeight: Math.round(contentItem.implicitHeight)

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Item {
            width: root.background.width
            height: root.background.height
            Rectangle {
                radius: root.background.radius
                anchors {
                    fill: parent
                    topMargin: root.Drag.active ? root.titleBarImplicitHeight : 0
                }
            }
        }
    }
    property bool droppable: false
    scale: (root.pressedButtons & Qt.LeftButton || root.Drag.active) ? (droppable ? 0.4 : 0.95) : 1
    Behavior on scale {
        NumberAnimation {
            id: scaleAnim
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Looks.transition.easing.bezierCurve.easeIn
        }
    }

    function closeWindow() {
        if (root.hyprlandClient?.address) {
            Hyprland.dispatch(`hl.dsp.window.close({window = "address:${root.hyprlandClient.address}"})`);
        }
    }

    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onClicked: event => {
        if (event.button === Qt.LeftButton) {
            GlobalStates.overviewOpen = false;
            if (root.hyprlandClient?.address) {
                Hyprland.dispatch(`hl.dsp.focus({window = "address:${root.hyprlandClient.address}"})`);
            }
        } else if (event.button === Qt.MiddleButton) {
            root.closeWindow();
            event.accepted = true;
        } else if (event.button === Qt.RightButton) {
            if (!windowMenu.visible)
                windowMenu.popup();
            else
                windowMenu.close();
        }
    }

    ColumnLayout {
        id: contentItem
        z: 2
        anchors.fill: parent
        spacing: 0

        RowLayout {
            id: titleBar
            opacity: root.Drag.active ? 0 : 1
            spacing: 8
            WAppIcon {
                Layout.leftMargin: 8
                Layout.alignment: Qt.AlignVCenter
                iconName: root.iconName
                implicitSize: 16
                tryCustomIcon: false
            }
            WText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                elide: Text.ElideRight
                text: root.hyprlandClient?.title ?? ""
            }
            CloseButton {
                implicitWidth: 32
                implicitHeight: 32
                padding: 8
                onClicked: root.closeWindow()
            }
        }

        ScreencopyView {
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Math.round(root.size.width)
            implicitHeight: Math.round(root.size.height)
            constraintSize: Qt.size(Math.round(root.size.width), Math.round(root.size.height))

            Behavior on implicitWidth {
                animation: Looks.transition.enter.createObject(this)
            }
            Behavior on implicitHeight {
                animation: Looks.transition.enter.createObject(this)
            }

            captureSource: root.toplevel ?? null
            live: GlobalStates.overviewOpen
        }
    }

    WMenu {
        id: windowMenu
        downDirection: true

        Action {
            enabled: Boolean(root.hyprlandClient?.floating)
            property bool isPinned: Boolean(root.hyprlandClient?.pinned)
            icon.name: isPinned ? "checkmark" : "empty"
            text: Translation.tr("Show this window on all desktops")
            onTriggered: {
                if (root.hyprlandClient?.address) {
                    Hyprland.dispatch(`hl.dsp.window.pin({window = "address:${root.hyprlandClient.address}"})`);
                }
            }
        }
        Action {
            icon.name: "empty"
            text: Translation.tr("Close")
            onTriggered: root.closeWindow()
        }
    }
}
