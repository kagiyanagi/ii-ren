pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One tailnet peer. Collapsed it is a status dot, a name and a route hint;
 * tapping reveals the actions, so five peers do not become a wall of buttons.
 */
Rectangle {
    id: root
    required property var modelData
    property bool expanded: false

    readonly property bool online: root.modelData?.online ?? false
    readonly property bool exitNode: root.modelData?.exitNode ?? false
    readonly property string osIcon: {
        switch (root.modelData?.os ?? "") {
        case "android": return "smartphone";
        case "iOS": return "smartphone";
        case "macOS": return "laptop_mac";
        case "windows": return "desktop_windows";
        default: return "dns";
        }
    }
    readonly property real padding: 12
    readonly property color colText: root.exitNode ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnLayer2
    readonly property color colSubtle: root.exitNode ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colSubtext

    Layout.fillWidth: true
    implicitHeight: peerColumn.implicitHeight + root.padding * 2
    radius: Appearance.rounding.normal
    color: root.exitNode ? Appearance.colors.colTertiaryContainer : Appearance.colors.colLayer2
    // The action row is laid out as soon as it starts to fade in, while the
    // height is still growing; without this it paints over the next peer.
    clip: true

    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    Behavior on implicitHeight { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }

    // A layer up from the card. The library default is layer 2, which is the
    // card itself, so the pills had no container until the card was hovered.
    component PeerAction: RippleButtonWithIcon {
        id: action
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colLayer3Hover
        colRipple: Appearance.colors.colLayer3Active
        colStateLayer: action.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
        colText: action.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
    }

    StateOverlay {
        anchors.fill: parent
        radius: root.radius
        contentColor: root.colText
        hover: cardArea.containsMouse
        press: cardArea.pressed
    }

    // Under the content column, so the action buttons keep their own clicks
    // and a tap on one never also folds the card.
    MouseArea {
        id: cardArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expanded = !root.expanded
    }

    ColumnLayout {
        id: peerColumn
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Item {
                implicitWidth: 24
                implicitHeight: 24
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.osIcon
                    iconSize: 20
                    fill: 1
                    color: root.online ? root.colText : root.colSubtle
                }
                Rectangle { // Presence dot
                    anchors {
                        right: parent.right
                        bottom: parent.bottom
                    }
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: Appearance.rounding.full
                    color: root.online ? Appearance.m3colors.m3success : Appearance.colors.colSubtext
                    border.width: 2
                    border.color: root.color
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    StyledText {
                        text: root.modelData?.name ?? ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: root.online ? root.colText : root.colSubtle
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Rectangle { // Exit node badge
                        visible: root.exitNode
                        implicitWidth: exitLabel.implicitWidth + 12
                        implicitHeight: exitLabel.implicitHeight + 4
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colTertiary
                        StyledText {
                            id: exitLabel
                            anchors.centerIn: parent
                            text: Translation.tr("Exit node")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnTertiary
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: {
                        const ip = root.modelData?.ip ?? "";
                        if (!root.online) return `${ip} · ${Translation.tr("offline")}`;
                        return `${ip} · ${root.modelData.direct ? Translation.tr("direct") : Translation.tr("relayed")}`;
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.colSubtle
                    elide: Text.ElideRight
                }
            }

            MaterialSymbol {
                text: "expand_more"
                iconSize: Appearance.font.pixelSize.larger
                color: root.colSubtle
                // The height change runs on elementMove, so the flip rides the
                // same spec and reads as one gesture.
                rotation: root.expanded ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }
        }

        // Fades out before the card's height drops, rather than vanishing on
        // the collapse's first frame. BluetoothDeviceItem's forget button.
        Flow {
            id: actions
            property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
            Layout.fillWidth: true
            opacity: {
                actions.fadeSpec = root.expanded ? Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit;
                return root.expanded ? 1 : 0;
            }
            visible: opacity > 0
            spacing: 6
            Behavior on opacity {
                NumberAnimation {
                    duration: actions.fadeSpec.duration
                    easing.type: actions.fadeSpec.type
                    easing.bezierCurve: actions.fadeSpec.bezierCurve
                }
            }

            PeerAction {
                materialIcon: "content_copy"
                mainText: Translation.tr("Copy IP")
                onClicked: Tailscale.copyIp(root.modelData.ip)
            }
            PeerAction {
                visible: root.online && (root.modelData?.ssh ?? false)
                materialIcon: "terminal"
                mainText: Translation.tr("SSH")
                onClicked: Tailscale.ssh(root.modelData.fqdn !== "" ? root.modelData.fqdn : root.modelData.ip)
            }
            PeerAction {
                visible: root.modelData?.taildrop ?? false
                materialIcon: "upload_file"
                mainText: Translation.tr("Send")
                onClicked: Tailscale.sendFiles(root.modelData.fqdn !== "" ? root.modelData.fqdn : root.modelData.ip)
            }
            PeerAction {
                visible: (root.modelData?.offersExit ?? false) && root.online
                toggled: root.exitNode
                materialIcon: "vpn_lock"
                mainText: root.exitNode ? Translation.tr("Stop routing") : Translation.tr("Route via")
                onClicked: Tailscale.setExitNode(root.exitNode ? "" : root.modelData.ip)
            }
        }
    }
}
