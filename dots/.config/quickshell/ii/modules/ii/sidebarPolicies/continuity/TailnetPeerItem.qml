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
    readonly property string osIcon: {
        switch (root.modelData?.os ?? "") {
        case "android": return "smartphone";
        case "iOS": return "smartphone";
        case "macOS": return "laptop_mac";
        case "windows": return "desktop_windows";
        default: return "dns";
        }
    }

    Layout.fillWidth: true
    implicitHeight: peerColumn.implicitHeight + 20
    radius: Appearance.rounding.normal
    color: root.modelData?.exitNode ? Appearance.colors.colTertiaryContainer
        : hoverHandler.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    Behavior on implicitHeight { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }

    HoverHandler { id: hoverHandler }
    TapHandler { onTapped: root.expanded = !root.expanded }

    ColumnLayout {
        id: peerColumn
        anchors {
            fill: parent
            margins: 10
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Item {
                implicitWidth: 26
                implicitHeight: 26
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.osIcon
                    iconSize: 20
                    fill: 1
                    color: root.online ? Appearance.colors.colOnLayer2 : Appearance.colors.colSubtext
                }
                Rectangle { // Presence dot
                    anchors {
                        right: parent.right
                        bottom: parent.bottom
                    }
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: Appearance.rounding.full
                    color: root.online ? Appearance.m3colors.m3success : Appearance.colors.colOutlineVariant
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
                    spacing: 5
                    StyledText {
                        text: root.modelData?.name ?? ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: root.online ? Appearance.colors.colOnLayer2 : Appearance.colors.colSubtext
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Rectangle { // Exit node badge
                        visible: root.modelData?.exitNode ?? false
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
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            visible: root.expanded
            spacing: 6

            RippleButtonWithIcon {
                materialIcon: "content_copy"
                mainText: Translation.tr("Copy IP")
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                onClicked: Tailscale.copyIp(root.modelData.ip)
            }
            RippleButtonWithIcon {
                visible: root.online && (root.modelData?.ssh ?? false)
                materialIcon: "terminal"
                mainText: Translation.tr("SSH")
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                onClicked: Tailscale.ssh(root.modelData.fqdn !== "" ? root.modelData.fqdn : root.modelData.ip)
            }
            RippleButtonWithIcon {
                visible: root.modelData?.taildrop ?? false
                materialIcon: "upload_file"
                mainText: Translation.tr("Send")
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                onClicked: Tailscale.sendFiles(root.modelData.fqdn !== "" ? root.modelData.fqdn : root.modelData.ip)
            }
            RippleButtonWithIcon {
                visible: (root.modelData?.offersExit ?? false) && root.online
                toggled: root.modelData?.exitNode ?? false
                materialIcon: "vpn_lock"
                mainText: (root.modelData?.exitNode ?? false) ? Translation.tr("Stop routing") : Translation.tr("Route via")
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                onClicked: Tailscale.setExitNode((root.modelData?.exitNode ?? false) ? "" : root.modelData.ip)
            }
        }
    }
}
