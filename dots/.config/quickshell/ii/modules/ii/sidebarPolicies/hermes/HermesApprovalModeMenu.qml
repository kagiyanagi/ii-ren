pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * How much Hermes is allowed to do before it has to ask -- a pill in the
 * composer's bottom row that opens a picker for `approvalMode` plus the
 * separate `yolo` override. Both setters round-trip through the gateway and
 * come back as a session-info event, so nothing here writes local state:
 * every label and every "selected" row is read straight off HermesService.
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
            // Same glyph HermesApprovalCard uses for a live risk prompt --
            // "off" is the mode where that prompt never gets to happen.
            icon: "gpp_maybe",
            label: Translation.tr("Off"),
            description: Translation.tr("Never checks -- it just acts.")
        }
    })

    readonly property var currentInfo: root.modeInfo[HermesService.approvalMode] ?? null
    readonly property bool modeKnown: root.currentInfo !== null
    // yolo means "don't ask" independently of the mode, so it reads as hot
    // even over "manual" -- a contradiction the gateway allows, and the pill
    // should not paper over.
    readonly property bool hot: root.modeKnown && (HermesService.approvalMode === "off" || HermesService.yolo)

    readonly property string tooltipText: {
        if (!root.modeKnown)
            return Translation.tr("Waiting to hear how this session is set up.");
        if (HermesService.yolo && HermesService.approvalMode !== "off")
            return Translation.tr("%1\nYolo is also on, so nothing is asked regardless.").arg(root.currentInfo.description);
        return root.currentInfo.description;
    }

    enabled: root.modeKnown
    pointingHandCursor: root.modeKnown
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

    releaseAction: () => pickerPopup.visible ? pickerPopup.close() : pickerPopup.open()

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
            text: root.currentInfo?.label ?? Translation.tr("Approvals")
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
            rotation: pickerPopup.visible ? 180 : 0
            Behavior on rotation {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    StyledToolTip {
        text: root.tooltipText
    }

    // One list row per mode -- selection comes straight from
    // HermesService.approvalMode, never a locally-guessed value.
    component ModeRow: RippleButton {
        id: modeRow

        property string mode: ""
        property string modeIcon: ""
        property string modeLabel: ""
        property string modeDescription: ""

        readonly property bool selected: HermesService.approvalMode === modeRow.mode
        readonly property bool isOff: modeRow.mode === "off"
        readonly property color onColor: modeRow.selected ? (modeRow.isOff ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnSecondaryContainer) : (modeRow.isOff ? Appearance.colors.colError : Appearance.colors.colOnLayer2)

        Layout.fillWidth: true
        implicitHeight: rowContent.implicitHeight + 8 * 2
        buttonRadius: Appearance.rounding.normal

        colBackground: modeRow.selected ? (modeRow.isOff ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer) : "transparent"
        colBackgroundHover: modeRow.selected ? (modeRow.isOff ? Appearance.colors.colErrorContainerHover : Appearance.colors.colSecondaryContainerHover) : Appearance.colors.colLayer2Hover

        releaseAction: () => HermesService.setApprovalMode(modeRow.mode)

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

    Popup {
        id: pickerPopup
        parent: root

        // Wide enough that a description is one or two lines, not three;
        // still a menu rather than a panel inside a 460px sidebar.
        width: 340
        padding: 12
        leftPadding: 12
        rightPadding: 12
        y: root.height + 10 // Opens downward -- this pill sits in the status strip up top
        x: {
            // Left-aligned with the pill by default, nudged inward only if
            // that would run the card past the window's edge (DockFolderPopup
            // clamps the same way, just against a whole-screen window).
            const globalLeft = root.mapToItem(null, 0, 0).x;
            const winWidth = root.QsWindow?.window?.width ?? (globalLeft + pickerPopup.width + 16);
            return Math.max(8 - globalLeft, Math.min(0, winWidth - 8 - pickerPopup.width - globalLeft));
        }

        transformOrigin: Item.TopLeft

        // ArrowPopup motion (DESIGN.md 9 / DockFolderPopup): open scale
        // 0.5->1.02->1 decelerating, close scale 1->0.5 accelerating, alpha
        // riding along underneath rather than driving the shape.
        enter: Transition {
            ParallelAnimation {
                SequentialAnimation {
                    NumberAnimation {
                        property: "scale"
                        from: 0.5
                        to: 1.02
                        duration: 200
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                    NumberAnimation {
                        property: "scale"
                        to: 1
                        duration: 200
                        easing.type: Easing.Bezier
                        easing.bezierCurve: [0.3, 0, 0.33, 1, 1, 1]
                    }
                }
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 83
                }
            }
        }

        exit: Transition {
            ParallelAnimation {
                NumberAnimation {
                    property: "scale"
                    to: 0.5
                    duration: 233
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                }
                SequentialAnimation {
                    PauseAnimation {
                        duration: 150
                    }
                    NumberAnimation {
                        property: "opacity"
                        to: 0
                        duration: 83
                    }
                }
            }
        }

        background: Item {
            StyledRectangularShadow {
                target: popupCard
            }

            Rectangle {
                id: popupCard
                anchors.fill: parent
                radius: Appearance.rounding.verylarge
                color: Appearance.m3colors.m3surfaceContainerHigh
            }
        }

        contentItem: ColumnLayout {
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                Layout.minimumWidth: 0
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
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

            Rectangle { // The blunt override -- kept visually separate and constantly cautionary, on or off
                Layout.fillWidth: true
                implicitHeight: yoloColumn.implicitHeight + 12 * 2
                radius: Appearance.rounding.large
                color: Appearance.colors.colErrorContainer

                ColumnLayout {
                    id: yoloColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 12
                    }
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.m3colors.m3onErrorContainer
                            text: "warning"
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.m3colors.m3onErrorContainer
                            text: Translation.tr("Skip approvals entirely")
                        }

                        StyledSwitch {
                            checked: HermesService.yolo
                            onToggled: HermesService.setYolo(checked)
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        lineHeight: 1.3
                        color: Appearance.m3colors.m3onErrorContainer
                        text: Translation.tr("Overrides everything above. Hermes can run commands on this machine without asking, ever. Only for when you're watching closely.")
                    }
                }
            }
        }
    }
}
