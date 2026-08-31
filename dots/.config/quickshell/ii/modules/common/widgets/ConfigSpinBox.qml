import qs.modules.common.widgets
import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property string text: ""
    property string icon
    property alias value: spinBoxWidget.value
    property alias stepSize: spinBoxWidget.stepSize
    property alias from: spinBoxWidget.from
    property alias to: spinBoxWidget.to
    
    property bool hovered: hoverHandler.hovered
    HoverHandler {
        id: hoverHandler
    }
    
    Layout.fillWidth: true
    readonly property bool wantsCard: true
    // Anchor margins don't feed implicitWidth the way Layout margins did, so
    // the row would ask for 16px less than it draws and clip its own spinner.
    implicitWidth: rowLayout.implicitWidth + 16
    implicitHeight: rowLayout.implicitHeight + 16

    HighlightOverlay {
        id: highlightOverlay
        anchors.fill: parent
        anchors.topMargin: -2
        anchors.bottomMargin: -2
        anchors.leftMargin: -4
        anchors.rightMargin: -4
    }

    SearchHandler {
        searchString: root.text
    }

    RowLayout {
        id: rowLayout
        // Centered rather than filled: the row is shorter than the card, and
        // filling would drag the label up to the top edge.
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 8
            rightMargin: 8
        }
        spacing: 8

        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            spacing: 10
            OptionalMaterialSymbol {
                icon: root.icon
                opacity: root.enabled ? 1 : 0.4
            }
            StyledText {
                id: labelWidget
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: root.text
                color: Appearance.colors.colOnSecondaryContainer
                opacity: root.enabled ? 1 : 0.4
            }
        }

        StyledSpinBox {
            id: spinBoxWidget
            Layout.fillWidth: false
            value: root.value
        }
    }
}
