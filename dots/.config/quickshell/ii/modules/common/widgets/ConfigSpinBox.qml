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

    // ContentGroup only hands a row the card's own corners and per-side reach
    // when the row exposes buttonRadius; without them the search flash painted
    // a rounding.small slab 4px short of the card on each side and 2px past it
    // top and bottom (5.6, 10.13). Declaring them makes the row the card's one
    // tile, so the card drives them and a spin box inside a ConfigRow picks up
    // only the edges it actually touches.
    property real buttonRadius: Appearance.rounding.verysmall
    property real topLeftRadius: buttonRadius
    property real topRightRadius: buttonRadius
    property real bottomLeftRadius: buttonRadius
    property real bottomRightRadius: buttonRadius
    property real backgroundBleedLeft: 0
    property real backgroundBleedRight: 0
    // Anchor margins don't feed implicitWidth the way Layout margins did, so
    // the row would ask for 16px less than it draws and clip its own spinner.
    implicitWidth: rowLayout.implicitWidth + 16
    implicitHeight: rowLayout.implicitHeight + 16

    HighlightOverlay {
        id: highlightOverlay
        x: -root.backgroundBleedLeft
        width: root.width + root.backgroundBleedLeft + root.backgroundBleedRight
        height: root.height
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
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
