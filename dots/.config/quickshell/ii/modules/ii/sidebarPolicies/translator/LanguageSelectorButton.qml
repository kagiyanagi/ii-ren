import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root
    property string displayText: ""
    property string hintText: ""
    // Kept through the collapse, so the text does not vanish before its box does.
    property string shownHint: ""
    onHintTextChanged: if (hintText.length > 0) shownHint = hintText
    // Sits in the language bar, on the page, which is layer 1.
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active
    buttonRadius: Appearance.rounding.full
    horizontalPadding: 16

    implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
    implicitHeight: 40

    contentItem: Item {
        anchors.centerIn: parent
        implicitWidth: languageRow.implicitWidth
        implicitHeight: languageText.implicitHeight
        RowLayout {
            id: languageRow
            anchors.centerIn: parent
            spacing: 0
            StyledText {
                id: languageText
                Layout.alignment: Qt.AlignVCenter
                // The pill is half a row, and "Português Brasileiro" is wider.
                Layout.maximumWidth: root.width - root.horizontalPadding * 2 - hint.width - arrow.width
                elide: Text.ElideRight
                text: root.displayText
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.small
            }
            Revealer {
                id: hint
                Layout.alignment: Qt.AlignVCenter
                reveal: root.hintText.length > 0
                StyledText {
                    leftPadding: 8
                    text: root.shownHint
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
            MaterialSymbol {
                id: arrow
                Layout.alignment: Qt.AlignVCenter
                iconSize: Appearance.font.pixelSize.hugeass
                text: "arrow_drop_down"
                color: Appearance.colors.colOnLayer2
            }
        }
    }
}
