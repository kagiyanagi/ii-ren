import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.services
import qs

Item {
    id: root
    
    readonly property string dockEffectivePosition: {
        const pos = Config.options?.dock.position ?? "bottom"
        if (pos !== "auto") return pos
        return (Config.options?.bar.bottom && !Config.options?.bar.vertical) ? "top" : "bottom"
    }
    readonly property bool isVertical: dockEffectivePosition === "left" || dockEffectivePosition === "right"
    property real marginScale: 0.3
    property color color: Appearance.colors.colOutlineVariant
    readonly property string style: Config.options?.dock?.separatorStyle ?? "Line"

    Rectangle {
        id: line
        visible: root.style === "Line"
        readonly property real currentMargin: Math.round((root.isVertical 
            ? root.width : root.height) * root.marginScale)

        readonly property real thickness: 3

        anchors.centerIn: parent
        width: root.isVertical ? root.width - currentMargin * 2 : thickness
        height: root.isVertical ? thickness : root.height - currentMargin * 2
        radius: Appearance.rounding.full
        color: root.color
    }

    Rectangle {
        id: dot
        visible: root.style === "Dot"
        anchors.centerIn: parent
        width: root.isVertical ? Math.min(root.width * 0.3, 6) : Math.min(root.height * 0.3, 6)
        height: width
        radius: width / 2
        color: root.color
    }
}