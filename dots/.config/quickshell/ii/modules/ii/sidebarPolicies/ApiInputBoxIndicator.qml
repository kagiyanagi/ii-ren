import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item { // Model indicator
    id: root
    property string icon: ""
    property string symbol: ""
    property string text: ""
    property string tooltipText: ""
    implicitHeight: rowLayout.implicitHeight + 4 * 2
    implicitWidth: rowLayout.implicitWidth + 4 * 2

    RowLayout {
        id: rowLayout
        // Fills rather than centres so the item can be given a width and have the
        // label elide inside it; at its implicit size this is identical to centring.
        anchors.fill: parent
        anchors.margins: 4
        // DESIGN.md 5.2: 8 between an icon and its label. Left unset it inherited
        // Qt's default 5, which is narrower than some Material Symbols glyphs
        // overhang their advance -- service_toolbox was printing over its own count.
        spacing: 8

        Loader {
            active: root.icon.length > 0
            sourceComponent: MaterialSymbol {
                text: root.icon
                iconSize: Appearance.font.pixelSize.normal
            }
        }
        Loader {
            active: root.symbol.length > 0
            sourceComponent: CustomIcon {
                source: root.symbol
                width: Appearance.font.pixelSize.normal
                height: Appearance.font.pixelSize.normal
                colorize: true
                color: Appearance.colors.colPrimary
            }
        }
        
        StyledText {
            id: providerName
            // elide only bites once the cell can actually be narrower than the text.
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.m3colors.m3onSurface
            elide: Text.ElideRight
            text: root.text
            animateChange: true
        }
    }

    Loader {
        active: root.tooltipText?.length > 0
        anchors.fill: parent
        sourceComponent: MouseArea {
            id: mouseArea
            hoverEnabled: true

            StyledToolTip {
                id: toolTip
                extraVisibleCondition: false
                alternativeVisibleCondition: mouseArea.containsMouse // Show tooltip when hovered
                text: root.tooltipText
            }
        }
    }
}
