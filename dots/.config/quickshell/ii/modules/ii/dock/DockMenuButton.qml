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
    // Defaults are the dock menus' dense rows; the desktop menu overrides them
    // for the launcher popup's roomier ones.
    property real contentSpacing: 6
    property real sidePadding: 2
    property real symbolSize: 18
    property real fontSize: Appearance.font.pixelSize.small
    signal triggered()

    implicitHeight: 35
    buttonRadius: Appearance.rounding.normal
    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    releaseAction: () => root.triggered()

    readonly property color contentColor: isDestructive ? Appearance.colors.colError : Appearance.colors.colOnLayer0

    contentItem: RowLayout {
        spacing: root.contentSpacing
        anchors {
            left: parent.left
            right: parent.right
            leftMargin: root.sidePadding
            rightMargin: root.sidePadding
            verticalCenter: parent.verticalCenter
        }

        Loader {
            active: root.shapeString !== ""
            visible: active
            sourceComponent: MaterialShape {
                shapeString: root.shapeString
                implicitSize: root.symbolSize
                color: root.contentColor
            }
        }

        MaterialSymbol {
            visible: root.symbolName !== "" && root.shapeString === ""
            text: root.symbolName
            iconSize: root.symbolSize
            color: root.contentColor
        }

        StyledText {
            text: root.labelText
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignLeft
            font.pixelSize: root.fontSize
            color: root.contentColor
        }
    }
}