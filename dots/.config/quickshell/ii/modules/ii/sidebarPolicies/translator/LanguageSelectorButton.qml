import qs
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
    // Sits on a TextCanvas card, which is layer 2.
    colBackground: Appearance.colors.colLayer3
    colBackgroundHover: Appearance.colors.colLayer3Hover
    colRipple: Appearance.colors.colLayer3Active

    implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
    implicitHeight: contentItem.implicitHeight + verticalPadding * 2

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
                Layout.leftMargin: 5
                text: root.displayText
                color: Appearance.colors.colOnLayer3
                font.pixelSize: Appearance.font.pixelSize.small
            }
            Revealer {
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
                Layout.alignment: Qt.AlignVCenter
                iconSize: Appearance.font.pixelSize.hugeass
                text: "arrow_drop_down"
                color: Appearance.colors.colOnLayer3
            }
        }
    }
}
