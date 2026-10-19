pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * How much the agent is allowed to do before it has to ask -- a pill in the
 * status strip that opens a picker for `approvalMode`. The setter round-trips
 * through the bridge and comes back as a session-info event, so nothing here
 * writes local state: every label and every "selected" row is read straight off
 * AgentService. Each agent maps the three modes onto its own permission modes
 * (scripts/agent/*_backend.py).
 */
RippleButton {
    id: root

    // Keyed on approval_mode so the pill, the tooltip and the picker rows
    // all draw from one place instead of repeating the same three strings.
    readonly property var modeInfo: ({
        manual: {
            icon: "back_hand",
            label: Translation.tr("Manual"),
            description: Translation.tr("Checks with you before every action.")
        },
        smart: {
            icon: "shield",
            label: Translation.tr("Smart"),
            description: Translation.tr("Checks with you only when something looks risky.")
        },
        off: {
            // Same glyph AgentApprovalCard uses for a live risk prompt --
            // "off" is the mode where that prompt never gets to happen.
            icon: "gpp_maybe",
            label: Translation.tr("Off"),
            description: Translation.tr("Never checks, with full access to this machine. Only for when you're watching closely.")
        }
    })

    readonly property var currentInfo: root.modeInfo[AgentService.approvalMode] ?? null
    readonly property bool modeKnown: root.currentInfo !== null
    readonly property bool hot: root.modeKnown && AgentService.approvalMode === "off"

    readonly property string tooltipText: {
        if (!root.modeKnown)
            return Translation.tr("This session is set to “%1”, which this shell has no setting for. Pick one below.").arg(AgentService.approvalMode);
        return root.currentInfo.description;
    }

    buttonRadius: Appearance.rounding.full

    // Hugs its content so the hover state is a compact chip around the label,
    // the same visual weight as the flat StatusItems either side of it. The
    // padding is the button's own, and is counted in both implicit sizes --
    // leave it out and the background stops short of the trailing chevron.
    verticalPadding: 4
    horizontalPadding: 8
    implicitHeight: contentRow.implicitHeight + topPadding + bottomPadding
    implicitWidth: contentRow.implicitWidth + leftPadding + rightPadding

    colBackground: root.hot ? Appearance.colors.colErrorContainer : "transparent"
    colBackgroundHover: root.hot ? Appearance.colors.colErrorContainerHover : Appearance.colors.colLayer2Hover
    colBackgroundActive: root.hot ? Appearance.colors.colErrorContainerActive : Appearance.colors.colLayer2Active

    releaseAction: () => picker.toggle(root)

    contentItem: RowLayout {
        id: contentRow
        spacing: 4

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: root.currentInfo?.icon ?? "shield"
            iconSize: Appearance.font.pixelSize.huge
            fill: root.hot ? 1 : 0
            color: root.hot ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colSubtext
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.hot ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colSubtext
            text: root.currentInfo?.label ?? AgentService.approvalMode
            animateChange: true
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        MaterialSymbol { // Same "this opens a picker" chevron StyledComboBox uses
            Layout.alignment: Qt.AlignVCenter
            text: "keyboard_arrow_down"
            iconSize: Appearance.font.pixelSize.smallest
            color: root.hot ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colSubtext
            rotation: picker.shown ? 180 : 0
            Behavior on rotation {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    StyledToolTip {
        text: root.tooltipText
        extraVisibleCondition: !picker.shown // not over its own open card
    }

    // One list row per mode -- selection comes straight from
    // AgentService.approvalMode, never a locally-guessed value.
    component ModeRow: RippleButton {
        id: modeRow

        property string mode: ""
        property string modeIcon: ""
        property string modeLabel: ""
        property string modeDescription: ""

        readonly property bool selected: AgentService.approvalMode === modeRow.mode
        readonly property bool isOff: modeRow.mode === "off"
        readonly property color onColor: modeRow.selected ? (modeRow.isOff ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnSecondaryContainer) : (modeRow.isOff ? Appearance.colors.colError : Appearance.colors.colOnSurface)

        Layout.fillWidth: true
        implicitHeight: rowContent.implicitHeight + 8 * 2
        buttonRadius: Appearance.rounding.normal

        colBackground: modeRow.selected ? (modeRow.isOff ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer) : "transparent"
        // Unselected rows sit on the popover's opaque card, which no colLayer
        // token is solved for, so their states are films of the content colour
        // over it: hover 0.08, pressed 0.10 (DESIGN.md 3.1).
        colBackgroundHover: modeRow.selected ? (modeRow.isOff ? Appearance.colors.colErrorContainerHover : Appearance.colors.colSecondaryContainerHover) : ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.92)
        colRipple: ColorUtils.transparentize(modeRow.onColor, 0.9)
        colStateLayer: modeRow.onColor

        releaseAction: () => AgentService.setApprovalMode(modeRow.mode)

        contentItem: RowLayout {
            id: rowContent
            spacing: 12

            MaterialSymbol {
                Layout.leftMargin: 12
                Layout.alignment: Qt.AlignVCenter
                text: modeRow.modeIcon
                iconSize: Appearance.font.pixelSize.normal
                fill: modeRow.selected ? 1 : 0
                color: modeRow.onColor
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
                    color: modeRow.onColor
                    text: modeRow.modeLabel
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    lineHeight: 1.3
                    color: Appearance.colors.colSubtext
                    text: modeRow.modeDescription
                }
            }

            MaterialSymbol {
                Layout.rightMargin: 12
                Layout.alignment: Qt.AlignVCenter
                visible: modeRow.selected
                text: "check"
                iconSize: Appearance.font.pixelSize.normal
                color: modeRow.onColor
            }
        }
    }

    // Hangs from the pill's bottom centre: the pill sits in the status strip up
    // top, so the menu opens downward. Wide enough that a description is one
    // or two lines, not three; still a menu rather than a panel.
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
            text: Translation.tr("Act without asking?")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            ModeRow {
                mode: "manual"
                modeIcon: root.modeInfo.manual.icon
                modeLabel: root.modeInfo.manual.label
                modeDescription: root.modeInfo.manual.description
            }
            ModeRow {
                mode: "smart"
                modeIcon: root.modeInfo.smart.icon
                modeLabel: root.modeInfo.smart.label
                modeDescription: root.modeInfo.smart.description
            }
            ModeRow {
                mode: "off"
                modeIcon: root.modeInfo.off.icon
                modeLabel: root.modeInfo.off.label
                modeDescription: root.modeInfo.off.description
            }
        }
    }
}
