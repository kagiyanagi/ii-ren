import qs.modules.common.widgets
import qs.modules.common.functions
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

    Layout.fillWidth: true
    implicitHeight: 48

    readonly property bool wantsCard: true

    Rectangle {
        anchors.fill: parent
        color: ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
        radius: Appearance.rounding.verysmall
        opacity: root.enabled ? 1 : 0.4

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

                onTextChanged: {
                    if (root.inputText !== text) {
                        root.inputText = text;
                    }
                }
            }
        }
    }
}
