import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property string title
    property string icon: ""
    property string tooltip: ""
    property bool collapsible: false
    property bool expanded: false
    property list<string> stringMap: []
    default property alias contentData: sectionContent.contentData

    readonly property color tintBackground: Appearance.colors.colPrimaryContainer
    readonly property color tintForeground: Appearance.colors.colOnPrimaryContainer

    Layout.fillWidth: true
    spacing: 10

    Component.onCompleted: {
        if (page?.register == false) return
        // console.log("KEYWORDS", root.stringMap)
        if (!page?.index) return
        SearchRegistry.registerSection({
            pageIndex: page?.index,
            title: root.title,
            searchStrings: root.stringMap.slice(),
            yPos: root.y
        })
    }

    function addKeyword(word) {
        if (!word) return
        // console.log("ADD KEYWORD", word)
        stringMap.push(word)
    }

    SearchHandler {
        searchString: root.title
    }

    RowLayout {
        id: headerRow
        spacing: 12
        Layout.leftMargin: 4

        Rectangle {
            visible: root.icon.length > 0
            opacity: 1 - highlightOverlay.opacity
            implicitWidth: 38
            implicitHeight: 38
            radius: Appearance.rounding.small
            color: root.tintBackground

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.icon
                iconSize: Appearance.font.pixelSize.huge
                fill: 1
                color: root.tintForeground
            }
        }
        StyledText {
            opacity: 1 - highlightOverlay.opacity
            text: root.title
            font.pixelSize: Appearance.font.pixelSize.huge
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer0
        }
        MaterialSymbol {
            opacity: 1 - highlightOverlay.opacity
            visible: root.tooltip && root.tooltip.length > 0
            text: "info"
            iconSize: Appearance.font.pixelSize.larger

            color: Appearance.colors.colOnSecondaryContainer
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
            iconSize: Appearance.font.pixelSize.huge
            color: Appearance.colors.colOnLayer0
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
