import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A settings row whose control is too wide to sit beside its label - chips, a
 * combo box, a field: icon, label and an optional summary on top, the control
 * below at full width, all on one card, as ConfigSlider puts its track. A
 * subsection header over a bare control left every such choice 8px in from
 * the switch rows around it, at a width of its own. Children go under the
 * label, on the same insets as the label.
 */
ColumnLayout {
    id: root
    property string text
    property string buttonIcon
    // A second line under the label, as on ConfigSwitch. Empty takes no room.
    property string summary
    default property alias content: body.data

    readonly property bool wantsCard: true
    Layout.fillWidth: true
    spacing: 0

    SearchHandler {
        visible: false // Root is a layout; don't take up a cell
        searchString: root.text
    }

    // On ConfigSwitch's 12 and 8 insets, so icon and label line up with the
    // switch rows in the same run. Disabled dims the header only: the control
    // below already dims itself, and a 0.4 on the whole row made it 0.16 (3.6).
    RowLayout {
        opacity: root.enabled ? 1 : 0.4
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.topMargin: 12
        spacing: 10

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        OptionalMaterialSymbol {
            opacity: 1 - highlightOverlay.opacity
            icon: root.buttonIcon
            iconSize: Appearance.font.pixelSize.larger
        }
        ColumnLayout {
            opacity: 1 - highlightOverlay.opacity
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 2
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.text
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                wrapMode: Text.Wrap
                text: root.summary
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
        HighlightOverlay {
            id: highlightOverlay
            visible: false
        }
    }

    ColumnLayout {
        id: body
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.topMargin: 8
        Layout.bottomMargin: 12
        spacing: 8
    }
}
