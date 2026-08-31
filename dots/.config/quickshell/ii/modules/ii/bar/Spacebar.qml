import QtQuick
import qs.modules.common
import qs.services

Item {
    id: root

    property bool vertical: false
    property var modelData: null

    readonly property string itemStyle: {
        const raw = (modelData && (modelData.style || modelData.type)) ? (modelData.style || modelData.type) : "pipe"
        const s = raw.toString().toLowerCase()
        if (s === "line" || s === "pipe") return "pipe"
        if (s === "dot" || s === "circle") return "dot"
        if (s === "dash" || s === "hyphen") return "dash"
        if (s === "empty" || s === "space" || s === "none") return "empty"
        return "pipe"
    }

    readonly property real leftPadding: Math.max(0, Number(modelData && modelData.leftPadding !== undefined ? modelData.leftPadding : (modelData && modelData.paddingLeft !== undefined ? modelData.paddingLeft : 4)))
    readonly property real rightPadding: Math.max(0, Number(modelData && modelData.rightPadding !== undefined ? modelData.rightPadding : (modelData && modelData.paddingRight !== undefined ? modelData.paddingRight : 4)))
    readonly property color color: Appearance.colors.colOutlineVariant
    readonly property real marginScale: 0.3
    readonly property real thickness: 3

    readonly property real contentSpan: {
        if (itemStyle === "pipe") return thickness
        if (itemStyle === "dot") return Math.min((root.vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight) * marginScale, 6)
        if (itemStyle === "dash") return 12
        return 0
    }

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : (leftPadding + contentSpan + rightPadding)
    implicitHeight: root.vertical ? (leftPadding + contentSpan + rightPadding) : Appearance.sizes.barHeight

    Behavior on implicitWidth {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }
    Behavior on implicitHeight {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    Item {
        id: visualContainer
        anchors {
            left: root.vertical ? parent.left : undefined
            right: root.vertical ? parent.right : undefined
            top: root.vertical ? undefined : parent.top
            bottom: root.vertical ? undefined : parent.bottom
            verticalCenter: root.vertical ? undefined : parent.verticalCenter
            horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        }
        x: root.vertical ? 0 : root.leftPadding
        y: root.vertical ? root.leftPadding : 0
        width: root.vertical ? root.width : root.contentSpan
        height: root.vertical ? root.contentSpan : root.height

        // Pipe (Line) - Matches DockSeparator.qml
        Rectangle {
            id: pipe
            visible: root.itemStyle === "pipe"
            readonly property real currentMargin: Math.round((root.vertical ? root.width : root.height) * root.marginScale)
            anchors.centerIn: parent
            width: root.vertical ? root.width - currentMargin * 2 : root.thickness
            height: root.vertical ? root.thickness : root.height - currentMargin * 2
            radius: Appearance.rounding.full
            color: root.color

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        // Dot
        Rectangle {
            id: dot
            visible: root.itemStyle === "dot"
            anchors.centerIn: parent
            width: root.vertical ? Math.min(root.width * root.marginScale, 6) : Math.min(root.height * root.marginScale, 6)
            height: width
            radius: Appearance.rounding.full
            color: root.color

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        // Dash
        Rectangle {
            id: dash
            visible: root.itemStyle === "dash"
            anchors.centerIn: parent
            width: root.vertical ? root.thickness : 12
            height: root.vertical ? 12 : root.thickness
            radius: Appearance.rounding.full
            color: root.color

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}
