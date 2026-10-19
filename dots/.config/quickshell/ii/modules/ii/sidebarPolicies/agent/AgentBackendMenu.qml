pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Which agent answers -- the connection indicator in the status strip, named by
 * the agent, which opens a picker over the agents installed here (Claude Code,
 * Codex, Antigravity). Picking one restarts the bridge on it, so the chats, model
 * list and memory that follow are that agent's own. Every "selected" row and status line
 * is read off AgentService, as AgentApprovalModeMenu does.
 */
RippleButton {
    id: root

    readonly property bool failed: AgentService.missing || (!AgentService.ready && !AgentService.starting && AgentService.lastError.length > 0)
    readonly property string statusLine: {
        if (AgentService.missing)
            return Translation.tr("No agent installed");
        if (AgentService.ready)
            return AgentService.planName.length > 0 ? Translation.tr("Connected · %1").arg(AgentService.planName) : Translation.tr("Connected");
        if (root.failed)
            return AgentService.lastError;
        // A first-use download says how far along it is rather than "Connecting…".
        return AgentService.setupText.length > 0 ? AgentService.setupText : Translation.tr("Connecting…");
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
            text: AgentService.ready ? "cloud_done" : root.failed ? "cloud_off" : "cloud_sync"
            iconSize: Appearance.font.pixelSize.huge
            color: root.failed ? Appearance.colors.colError : Appearance.colors.colSubtext
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        StyledText {
            // Always named: which agent -- and whose plan -- answers the next
            // message has to be obvious before it goes out.
            visible: !AgentService.missing
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: 120
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: AgentService.agentName
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
        text: Translation.tr("%1 · %2").arg(AgentService.agentName).arg(root.statusLine)
        extraVisibleCondition: !picker.shown
    }

    component BackendRow: RippleButton {
        id: backendRow

        required property var modelData
        readonly property bool selected: AgentService.backend?.id === backendRow.modelData.id
        readonly property bool rowFailed: backendRow.selected && root.failed
        readonly property color onColor: backendRow.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface

        Layout.fillWidth: true
        implicitHeight: rowContent.implicitHeight + 8 * 2
        buttonRadius: Appearance.rounding.normal

        colBackground: backendRow.selected ? Appearance.colors.colSecondaryContainer : "transparent"
        // Same films over the popover's opaque card as the approval menu's rows.
        colBackgroundHover: backendRow.selected ? Appearance.colors.colSecondaryContainerHover : ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.92)
        colRipple: ColorUtils.transparentize(backendRow.onColor, 0.9)
        colStateLayer: backendRow.onColor

        releaseAction: () => {
            AgentService.setBackend(backendRow.modelData.id);
            picker.close();
        }

        contentItem: RowLayout {
            id: rowContent
            spacing: 12

            MaterialSymbol {
                Layout.leftMargin: 12
                Layout.alignment: Qt.AlignVCenter
                text: ({ codex: "code", antigravity: "rocket_launch" })[backendRow.modelData.id] ?? "auto_awesome"
                iconSize: Appearance.font.pixelSize.normal
                fill: backendRow.selected ? 1 : 0
                color: backendRow.onColor
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
                    color: backendRow.onColor
                    text: backendRow.modelData.label
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
                    color: backendRow.rowFailed ? Appearance.colors.colError : Appearance.colors.colSubtext
                    text: backendRow.selected ? root.statusLine : backendRow.modelData.plan
                }
            }

            MaterialSymbol {
                Layout.rightMargin: 12
                Layout.alignment: Qt.AlignVCenter
                visible: backendRow.selected
                text: "check"
                iconSize: Appearance.font.pixelSize.normal
                color: backendRow.onColor
            }
        }
    }

    // Hangs from the pill's bottom centre, as the approval menu beside it does.
    AgentPopover {
        id: picker

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            Layout.minimumWidth: 0
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnSurface
            text: Translation.tr("Which agent should answer?")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: AgentService.backends
                delegate: BackendRow {}
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
            text: Translation.tr("Each runs as its own program, signed in on its own, and its chats stay with it. Install Claude Code, Codex or Antigravity to see it here.")
        }
    }
}
