import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RippleButton { // Right sidebar button
    id: rightSidebarButton

    property bool vertical: false

    Layout.alignment: vertical ? (Qt.AlignBottom | Qt.AlignHCenter) : (Qt.AlignRight | Qt.AlignVCenter)
    Layout.rightMargin: vertical ? 0 : Appearance.rounding.screenRounding
    Layout.bottomMargin: vertical ? Appearance.rounding.screenRounding : 0
    Layout.fillWidth: false
    Layout.fillHeight: false

    implicitWidth: indicatorsLayout.implicitWidth + (vertical ? 6 : 10) * 2
    implicitHeight: indicatorsLayout.implicitHeight + (vertical ? 4 : 5) * 2

    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    toggled: GlobalStates.sidebarRightOpen
    property color colText: toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0

    Behavior on colText {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    onPressed: {
        GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
    }

    // GridLayout with an unbounded row/column count is a RowLayout or a
    // ColumnLayout depending on flow, so one layout covers both orientations.
    GridLayout {
        id: indicatorsLayout
        anchors.centerIn: parent
        flow: rightSidebarButton.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rowSpacing: 0
        columnSpacing: 0

        // Gaps are per-item margins rather than layout spacing so a collapsed
        // revealer takes up no space at all. 16 is the 4dp grid's section gap;
        // it used to be 15, which is not on it (5.1).
        property real realSpacing: rightSidebarButton.vertical ? 6 : 16

        IndicatorRevealer {
            reveal: Idle.inhibit ?? false
            icon: "local_cafe"
        }
        IndicatorRevealer {
            reveal: Audio.sink?.audio?.muted ?? false
            icon: "volume_off"
        }
        IndicatorRevealer {
            reveal: Audio.source?.audio?.muted ?? false
            icon: "mic_off"
        }
        IndicatorRevealer {
            reveal: LocationService.available && !LocationService.enabled
            icon: "location_disabled"
        }
        HyprlandXkbIndicator {
            vertical: rightSidebarButton.vertical
            Layout.alignment: rightSidebarButton.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            Layout.rightMargin: rightSidebarButton.vertical ? 0 : indicatorsLayout.realSpacing
            Layout.bottomMargin: rightSidebarButton.vertical ? indicatorsLayout.realSpacing : 0
            color: rightSidebarButton.colText
        }
        // The one indicator whose content is not a bare symbol, so it spells the
        // revealer out instead of reusing IndicatorRevealer. It used to override
        // implicitWidth/implicitHeight, which replaced the bindings Revealer
        // picks its exit spec from -- the badge therefore left on the enter
        // curve. Revealer's own childrenRect gives the same size: the ping sits
        // inside the symbol's bounds.
        Revealer {
            id: notificationRevealer
            vertical: rightSidebarButton.vertical
            reveal: Notifications.silent || Notifications.unread > 0
            Layout.fillHeight: !rightSidebarButton.vertical
            Layout.fillWidth: rightSidebarButton.vertical

            Layout.rightMargin: {
                notificationRevealer.pickRevealSpec();
                return rightSidebarButton.vertical ? 0 : (notificationRevealer.reveal ? indicatorsLayout.realSpacing : 0);
            }
            Layout.bottomMargin: {
                notificationRevealer.pickRevealSpec();
                return rightSidebarButton.vertical ? (notificationRevealer.reveal ? indicatorsLayout.realSpacing : 0) : 0;
            }

            Behavior on Layout.rightMargin {
                NumberAnimation {
                    alwaysRunToEnd: false
                    duration: notificationRevealer.revealSpec.duration
                    easing.type: notificationRevealer.revealSpec.type
                    easing.bezierCurve: notificationRevealer.revealSpec.bezierCurve
                }
            }
            Behavior on Layout.bottomMargin {
                NumberAnimation {
                    alwaysRunToEnd: false
                    duration: notificationRevealer.revealSpec.duration
                    easing.type: notificationRevealer.revealSpec.type
                    easing.bezierCurve: notificationRevealer.revealSpec.bezierCurve
                }
            }

            NotificationUnreadCount {}
        }
        IndicatorRevealer {
            reveal: Network.hotspotToggled
            icon: "wifi_tethering"
        }
        MaterialSymbol {
            text: Network.materialSymbol
            iconSize: Appearance.font.pixelSize.larger
            color: rightSidebarButton.colText
        }
        MaterialSymbol {
            Layout.leftMargin: rightSidebarButton.vertical ? 0 : indicatorsLayout.realSpacing
            Layout.topMargin: rightSidebarButton.vertical ? indicatorsLayout.realSpacing : 0
            visible: BluetoothStatus.available
            text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
            iconSize: Appearance.font.pixelSize.larger
            color: rightSidebarButton.colText
        }
    }

    /**
     * One indicator that slides in and out of the cluster. Eight copies of this
     * block used to sit inline, and the first of them filled height
     * unconditionally, so in the vertical bar it stretched where its seven
     * siblings did not.
     *
     * The gap rides Revealer's own `revealSpec` rather than a spec of its own:
     * the width and the gap beside it are one movement, and two specs on it
     * meant the neighbours finished sliding 370ms before the hole between them
     * closed. `pickRevealSpec()` is called from inside the margin binding for
     * the reason Revealer documents -- a Behavior bakes its curve when the
     * binding that writes its property runs, and nothing orders these two
     * bindings against each other (2.9).
     */
    component IndicatorRevealer: Revealer {
        id: indicator

        required property string icon

        vertical: rightSidebarButton.vertical
        Layout.fillHeight: !rightSidebarButton.vertical
        Layout.fillWidth: rightSidebarButton.vertical

        Layout.rightMargin: {
            indicator.pickRevealSpec();
            return rightSidebarButton.vertical ? 0 : (indicator.reveal ? indicatorsLayout.realSpacing : 0);
        }
        Layout.bottomMargin: {
            indicator.pickRevealSpec();
            return rightSidebarButton.vertical ? (indicator.reveal ? indicatorsLayout.realSpacing : 0) : 0;
        }

        Behavior on Layout.rightMargin {
            NumberAnimation {
                alwaysRunToEnd: false
                duration: indicator.revealSpec.duration
                easing.type: indicator.revealSpec.type
                easing.bezierCurve: indicator.revealSpec.bezierCurve
            }
        }
        Behavior on Layout.bottomMargin {
            NumberAnimation {
                alwaysRunToEnd: false
                duration: indicator.revealSpec.duration
                easing.type: indicator.revealSpec.type
                easing.bezierCurve: indicator.revealSpec.bezierCurve
            }
        }

        MaterialSymbol {
            text: indicator.icon
            iconSize: Appearance.font.pixelSize.larger
            color: rightSidebarButton.colText
        }
    }
}
