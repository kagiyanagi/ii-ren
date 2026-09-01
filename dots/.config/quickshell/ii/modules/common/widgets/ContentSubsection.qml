import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property string title: ""
    property string icon: ""
    property string tooltip: ""
    property bool collapsible: false
    property bool expanded: false
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
        id: headerRow
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

        MaterialSymbol {
            visible: root.collapsible
            text: "keyboard_arrow_down"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
            rotation: root.expanded ? 0 : -90
            Behavior on rotation {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
        }
    }

    MouseArea {
        parent: headerRow
        anchors.fill: parent
        enabled: root.collapsible
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expanded = !root.expanded
    }
    
    Item {
        Layout.fillWidth: true
        implicitHeight: root.expanded || !root.collapsible ? sectionContent.implicitHeight : 0
        visible: root.expanded || !root.collapsible
        
        ContentGroup {
            id: sectionContent
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
        }
    }
}
