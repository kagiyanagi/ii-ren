pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Which Hermes the sidebar is talking to -- the connection indicator in the
 * status strip, which opens a picker over the desktop app's gateways. Picking
 * one restarts the gateway on that host, so the history, memory and
 * personality that follow are that host's. Every "selected" row and status
 * line is read off HermesService, as HermesApprovalModeMenu does.
 */
RippleButton {
    id: root

    readonly property bool failed: HermesService.missing || (!HermesService.ready && !HermesService.starting && HermesService.lastError.length > 0)
    readonly property string statusLine: {
        if (HermesService.missing)
            return HermesService.remote ? Translation.tr("hermes-agent is not installed there") : Translation.tr("hermes-agent is not installed");
        if (HermesService.ready)
            return Translation.tr("Connected");
        if (root.failed)
            return HermesService.lastError;
        return Translation.tr("Connecting…");
    }

    buttonRadius: Appearance.rounding.full
    verticalPadding: 4
    horizontalPadding: 8
    implicitHeight: contentRow.implicitHeight + topPadding + bottomPadding
    implicitWidth: contentRow.implicitWidth + leftPadding + rightPadding

    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colBackgroundActive: Appearance.colors.colLayer2Active

    releaseAction: () => picker.toggle(root)

    contentItem: RowLayout {
        id: contentRow
        spacing: 4

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: HermesService.ready ? "cloud_done" : root.failed ? "cloud_off" : "cloud_sync"
            iconSize: Appearance.font.pixelSize.huge
            color: root.failed ? Appearance.colors.colError : Appearance.colors.colSubtext
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        StyledText {
            // Named only when it is not this machine: the default needs no label,
            // and a remote one has to be obvious before the next message goes out.
            visible: HermesService.remote
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: 120
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: HermesService.gateway.label
            animateChange: true
        }

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: "keyboard_arrow_down"
            iconSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
            rotation: picker.shown ? 180 : 0
            Behavior on rotation {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
        }
    }

    StyledToolTip {
        text: Translation.tr("%1 · %2").arg(HermesService.gateway.label).arg(root.statusLine)
        extraVisibleCondition: !picker.shown
    }

    component GatewayRow: RippleButton {
        id: gatewayRow

        required property var modelData
        readonly property bool selected: HermesService.gateway.id === gatewayRow.modelData.id
        readonly property bool rowFailed: gatewayRow.selected && root.failed
        readonly property color onColor: gatewayRow.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface

        Layout.fillWidth: true
        implicitHeight: rowContent.implicitHeight + 8 * 2
        buttonRadius: Appearance.rounding.normal

        colBackground: gatewayRow.selected ? Appearance.colors.colSecondaryContainer : "transparent"
        // Same films over the popover's opaque card as the approval menu's rows.
        colBackgroundHover: gatewayRow.selected ? Appearance.colors.colSecondaryContainerHover : ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.92)
        colRipple: ColorUtils.transparentize(gatewayRow.onColor, 0.9)
        colStateLayer: gatewayRow.onColor

        releaseAction: () => {
            HermesService.setGateway(gatewayRow.modelData.id);
            picker.close();
        }

        contentItem: RowLayout {
            id: rowContent
            spacing: 12

            MaterialSymbol {
                Layout.leftMargin: 12
                Layout.alignment: Qt.AlignVCenter
                text: gatewayRow.modelData.kind === "local" ? "computer" : "dns"
                iconSize: Appearance.font.pixelSize.normal
                fill: gatewayRow.selected ? 1 : 0
                color: gatewayRow.onColor
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 4

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: gatewayRow.onColor
                    text: gatewayRow.modelData.label
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    lineHeight: 1.3
                    color: gatewayRow.rowFailed ? Appearance.colors.colError : Appearance.colors.colSubtext
                    text: gatewayRow.selected ? root.statusLine : gatewayRow.modelData.kind === "local" ? Translation.tr("Runs on this computer") : Translation.tr("%1 over SSH").arg(gatewayRow.modelData.user ? `${gatewayRow.modelData.user}@${gatewayRow.modelData.host}` : gatewayRow.modelData.host)
                }
            }

            MaterialSymbol {
                Layout.rightMargin: 12
                Layout.alignment: Qt.AlignVCenter
                visible: gatewayRow.selected
                text: "check"
                iconSize: Appearance.font.pixelSize.normal
                color: gatewayRow.onColor
            }
        }
    }

    // Hangs from the pill's bottom centre, as the approval menu beside it does.
    HermesPopover {
        id: picker

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            Layout.minimumWidth: 0
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnSurface
            text: Translation.tr("Where should Hermes run?")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: HermesService.gateways
                delegate: GatewayRow {}
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            lineHeight: 1.3
            color: Appearance.colors.colSubtext
            text: Translation.tr("Chats, memory and personality come from the gateway you pick. Add gateways in the Hermes app.")
        }
    }
}
