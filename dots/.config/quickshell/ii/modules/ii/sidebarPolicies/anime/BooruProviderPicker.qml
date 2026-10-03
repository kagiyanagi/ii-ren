pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarPolicies.hermes
import QtQuick
import QtQuick.Layouts

/**
 * Provider selection, opened from the composer's provider chip -- the same card
 * as Hermes' model picker. Few enough providers that it needs no search field.
 */
HermesPopover {
    id: root

    opensUp: true
    // Wide enough that the descriptions read whole; the panel clamps it.
    cardWidth: 400
    spacing: 2

    function pick(provider: string): void {
        if (provider !== Booru.currentProvider)
            Booru.setProvider(provider);
        root.close();
    }

    Repeater {
        model: Booru.providerList

        delegate: RippleButton {
            id: providerRow
            required property string modelData

            readonly property var provider: Booru.providers[providerRow.modelData]
            readonly property bool selected: providerRow.modelData === Booru.currentProvider
            readonly property color onColor: providerRow.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface

            Layout.fillWidth: true
            implicitHeight: rowContent.implicitHeight + 8 * 2
            buttonRadius: Appearance.rounding.normal

            colBackground: providerRow.selected ? Appearance.colors.colSecondaryContainer : "transparent"
            colBackgroundHover: providerRow.selected ? Appearance.colors.colSecondaryContainerHover : ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.92)
            colRipple: ColorUtils.transparentize(providerRow.onColor, 0.9)
            colStateLayer: providerRow.onColor

            releaseAction: () => root.pick(providerRow.modelData)

            contentItem: RowLayout {
                id: rowContent
                spacing: 12

                MaterialSymbol {
                    Layout.leftMargin: 12
                    Layout.alignment: Qt.AlignVCenter
                    text: "api"
                    iconSize: Appearance.font.pixelSize.normal
                    fill: providerRow.selected ? 1 : 0
                    color: providerRow.onColor
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
                        color: providerRow.onColor
                        text: providerRow.provider.name
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        visible: text.length > 0
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: providerRow.provider.description ?? ""
                    }
                }

                MaterialSymbol {
                    Layout.rightMargin: 12
                    Layout.alignment: Qt.AlignVCenter
                    visible: providerRow.selected
                    text: "check"
                    iconSize: Appearance.font.pixelSize.normal
                    color: providerRow.onColor
                }
            }
        }
    }
}
