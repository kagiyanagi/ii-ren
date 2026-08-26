import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root
    property string symbolName: ""
    property string shapeString: ""  
    property string labelText: ""
    property bool isDestructive: false
    signal triggered()

    implicitHeight: 35
    buttonRadius: Appearance.rounding.normal
    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    releaseAction: () => root.triggered()

    readonly property color contentColor: isDestructive ? Appearance.colors.colError : Appearance.colors.colOnLayer0

    contentItem: RowLayout {
        spacing: 6
        anchors {
            left: parent.left
            right: parent.right
            leftMargin: 2
            rightMargin: 2
            verticalCenter: parent.verticalCenter
        }

        Loader {
            active: root.shapeString !== ""
            visible: active
            sourceComponent: MaterialShape {
                shapeString: root.shapeString
                implicitSize: 18
                color: root.contentColor
            }
        }

        MaterialSymbol {
            visible: root.symbolName !== "" && root.shapeString === ""
            text: root.symbolName
            iconSize: 18
            color: root.contentColor
        }

        StyledText {
            text: root.labelText
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignLeft
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.contentColor
        }
    }
}