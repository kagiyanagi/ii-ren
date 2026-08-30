import QtQuick
import qs.modules.common
import qs.modules.common.widgets

MaterialShape {
    id: root
    property alias text: symbol.text
    property alias iconSize: symbol.iconSize
    property alias font: symbol.font
    property alias colSymbol: symbol.color
    property alias fill: symbol.fill
    property alias animateChange: symbol.animateChange
    property real padding: 8

    property bool rotateIconWithShape: false

    color: Appearance.colors.colSecondaryContainer
    shape: MaterialShape.Shape.Clover4Leaf
    implicitSize: iconSize + padding * 2

    Behavior on rotation {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    MaterialSymbol {
        id: symbol
        visible: !text.endsWith(".svg")
        anchors.centerIn: parent
        color: Appearance.colors.colOnSecondaryContainer
        rotation: !root.rotateIconWithShape ? 360 - root.rotation: root.rotation
    }

    CustomIcon {
        id: customIcon
        // Only point it at a file when the text really is one: hiding an image does
        // not stop it loading its source, so a Material Symbol name here had it
        // chasing an asset by that name on every icon change.
        readonly property bool isAsset: symbol.text.endsWith(".svg")

        visible: customIcon.isAsset
        source: customIcon.isAsset ? symbol.text : ""
        anchors.centerIn: parent
        width: symbol.iconSize
        height: symbol.iconSize
        color: symbol.color
        colorize: true
        rotation: symbol.rotation
    }
}
