import qs.modules.common.widgets
import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: root

    property string icon: ""
    property string text: ""
    property string inputText: ""
    property alias placeholderText: textField.placeholderText
    // For callers that commit once rather than on every keystroke.
    signal editingFinished()

    Layout.fillWidth: true
    implicitHeight: 48

    readonly property bool wantsCard: true

    // ContentGroup only hands a row the card's own corners and per-side reach
    // when the row exposes buttonRadius. The focus film needs both: without
    // them it squares the corners the card rounds and stops 8px short of its
    // edges (5.6, 10.13). The row used to paint a rounding.verysmall rectangle
    // of its own for the same reason and got away with it only because the
    // colour was transparentize(..., 1) - alpha zero, painting nothing.
    property real buttonRadius: Appearance.rounding.verysmall
    property real topLeftRadius: buttonRadius
    property real topRightRadius: buttonRadius
    property real bottomLeftRadius: buttonRadius
    property real bottomRightRadius: buttonRadius
    property real backgroundBleedLeft: 0
    property real backgroundBleedRight: 0

    opacity: root.enabled ? 1 : 0.4
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // The fourth state (3.1). A text field whose focus is only an activeFocus
    // boolean nothing renders is the case 3.7 names outright, and this row is
    // the keyboard-navigable part of the settings app.
    StateOverlay {
        x: -root.backgroundBleedLeft
        width: root.width + root.backgroundBleedLeft + root.backgroundBleedRight
        height: root.height
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        focused: textField.activeFocus
        contentColor: Appearance.colors.colOnLayer1
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        OptionalMaterialSymbol {
            icon: root.icon
            iconSize: Appearance.font.pixelSize.larger
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            text: root.text
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSecondaryContainer
            Layout.alignment: Qt.AlignVCenter
            // The label keeps its natural width but is allowed to shrink, so a
            // long one elides instead of drawing over the input beside it
            // (5.7, 10.17).
            Layout.minimumWidth: 0
            elide: Text.ElideRight
        }

        TextField {
            id: textField
            Layout.fillWidth: true
            Layout.fillHeight: true

            text: root.inputText
            color: Appearance.colors.colOnLayer1
            placeholderTextColor: Appearance.colors.colSubtext

            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Normal

            renderType: Text.NativeRendering
            selectedTextColor: Appearance.colors.colOnSecondaryContainer
            selectionColor: Appearance.colors.colSecondaryContainer
            background: null
            verticalAlignment: Text.AlignVCenter

            onEditingFinished: root.editingFinished()
            onTextChanged: {
                if (root.inputText !== text) {
                    root.inputText = text;
                }
            }
        }
    }
}
