import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property string title: ""
    property string tooltip: ""
    default property alias contentData: sectionContent.contentData

    Layout.fillWidth: true
    // Inset by exactly the card's bleed, so two subsections sharing a ConfigRow
    // end up with the row's gap between their cards instead of overlapping by it.
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    Layout.topMargin: 8
    // Side by side, the shorter one would otherwise centre itself and drop its
    // label below its neighbour's.
    Layout.alignment: Qt.AlignTop
    spacing: 4

    SearchHandler {
        searchString: root.title
    }

    RowLayout {
        Layout.leftMargin: 6
        ContentSubsectionLabel {
            opacity: 1 - highlightOverlay.opacity
            visible: root.title && root.title.length > 0
            text: root.title
        }
        MaterialSymbol {
            opacity: 1 - highlightOverlay.opacity
            visible: root.tooltip && root.tooltip.length > 0
            text: "info"
            iconSize: Appearance.font.pixelSize.large
            
            color: Appearance.colors.colSubtext
            MouseArea {
                id: infoMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.WhatsThisCursor
                StyledToolTip {
                    extraVisibleCondition: false
                    alternativeVisibleCondition: infoMouseArea.containsMouse
                    text: root.tooltip
                }
            }
        }
        HighlightOverlay {
            id: highlightOverlay
            visible: false
        }
        Item { Layout.fillWidth: true }
    }
    ContentGroup {
        id: sectionContent
    }
}
