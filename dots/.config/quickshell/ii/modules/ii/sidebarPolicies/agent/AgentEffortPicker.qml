pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * Reasoning effort, opened from the composer's effort chip -- the same card as the
 * model picker beside it. The levels are the current model's own
 * (`AgentService.effortOptions`, from the agent's inventory), so a model that
 * takes fewer shows fewer, and one that takes none has no chip at all. Few enough
 * that it needs no search field, as BooruProviderPicker.
 *
 * Picking applies to the running chat without restarting it, and the bridge
 * remembers it per agent for the next one.
 */
AgentPopover {
    id: root

    opensUp: true
    cardWidth: 320
    spacing: 2

    function pick(effort: string): void {
        AgentService.setEffort(effort);
        root.close();
    }

    StyledText {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        horizontalAlignment: Text.AlignHCenter
        Layout.minimumWidth: 0
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnSurface
        text: Translation.tr("How hard should it think?")
    }

    Repeater {
        model: AgentService.effortOptions

        delegate: RippleButton {
            id: effortRow
            required property var modelData

            readonly property bool selected: effortRow.modelData.id === AgentService.currentEffort
            readonly property color onColor: effortRow.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface

            Layout.fillWidth: true
            implicitHeight: rowContent.implicitHeight + 8 * 2
            buttonRadius: Appearance.rounding.normal

            colBackground: effortRow.selected ? Appearance.colors.colSecondaryContainer : "transparent"
            // Same films over the opaque card as the model picker's rows (3.1).
            colBackgroundHover: effortRow.selected ? Appearance.colors.colSecondaryContainerHover : ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.92)
            colRipple: ColorUtils.transparentize(effortRow.onColor, 0.9)
            colStateLayer: effortRow.onColor

            releaseAction: () => root.pick(effortRow.modelData.id)

            contentItem: RowLayout {
                id: rowContent
                spacing: 12

                MaterialSymbol {
                    Layout.leftMargin: 12
                    Layout.alignment: Qt.AlignVCenter
                    text: "neurology"
                    iconSize: Appearance.font.pixelSize.normal
                    fill: effortRow.selected ? 1 : 0
                    color: effortRow.onColor
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: effortRow.onColor
                        text: effortRow.modelData.label
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        visible: text.length > 0
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: effortRow.modelData.description ?? ""
                    }
                }

                MaterialSymbol {
                    Layout.rightMargin: 12
                    Layout.alignment: Qt.AlignVCenter
                    visible: effortRow.selected
                    text: "check"
                    iconSize: Appearance.font.pixelSize.normal
                    color: effortRow.onColor
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.topMargin: 4
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        lineHeight: 1.3
        color: Appearance.colors.colSubtext
        text: Translation.tr("More effort answers hard problems better, but is slower and uses more of your plan.")
    }
}
