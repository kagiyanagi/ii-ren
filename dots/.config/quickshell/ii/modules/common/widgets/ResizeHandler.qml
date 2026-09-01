import QtQuick
import qs.modules.common

Canvas {
    id: root

    required property Item anchorItem
    property bool hoverActive: false
    property bool locked: false
    required property real currentWidth
    property string resizeMode: "horizontal"
    property string corner: "top-right" // "top-right" | "bottom-right" | "bottom-left" | "top-left"

    signal resized(real newValue)
    signal resizedXY(real dx, real dy, real startWidth)
    signal resizeFinished()

    width: 62
    height: 62

    anchors {
        right: (root.corner === "top-right" || root.corner === "bottom-right") ? anchorItem.right : undefined
        left: (root.corner === "top-left" || root.corner === "bottom-left") ? anchorItem.left : undefined
        top: (root.corner === "top-right" || root.corner === "top-left") ? anchorItem.top : undefined
        bottom: (root.corner === "bottom-right" || root.corner === "bottom-left") ? anchorItem.bottom : undefined
        rightMargin: (root.corner === "top-right" || root.corner === "bottom-right") ? -8 : 0
        leftMargin: (root.corner === "top-left" || root.corner === "bottom-left") ? -8 : 0
        topMargin: (root.corner === "top-right" || root.corner === "top-left") ? -8 : 0
        bottomMargin: (root.corner === "bottom-right" || root.corner === "bottom-left") ? -8 : 0
    }

    opacity: (hoverActive || resizeArea.containsMouse || resizeArea.pressed) ? 0.85 : 0
    visible: opacity > 0 && !locked

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    property color strokeCol: Appearance.colors.colOnPrimaryContainer
    onStrokeColChanged: requestPaint()
    onCornerChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.strokeStyle = strokeCol
        ctx.lineWidth = 3
        ctx.lineCap = "round"
        ctx.beginPath()

        var startAngle = 0
        var endAngle = Math.PI * 0.5
        if (root.corner === "top-right") {
            startAngle = Math.PI * 1.5
            endAngle = Math.PI * 2.0
        } else if (root.corner === "bottom-left") {
            startAngle = Math.PI * 0.5
            endAngle = Math.PI
        } else if (root.corner === "top-left") {
            startAngle = Math.PI
            endAngle = Math.PI * 1.5
        }

        ctx.arc(width * 0.5, height * 0.5, width * 0.35, startAngle, endAngle)
        ctx.stroke()
    }

    MouseArea {
        id: resizeArea
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: {
            if (root.resizeMode !== "diagonal") return Qt.SizeHorCursor
            return (root.corner === "top-right" || root.corner === "bottom-left")
                ? Qt.SizeBDiagCursor
                : Qt.SizeFDiagCursor
        }
        preventStealing: true

        property real startValue: 0
        property real startX: 0
        property real startY: 0

        onPressed: (mouse) => {
            startValue = root.currentWidth
            var globalPos = mapToItem(null, mouse.x, mouse.y)
            startX = globalPos.x
            startY = globalPos.y
        }
        onPositionChanged: (mouse) => {
            if (!pressed) return
            var globalPos = mapToItem(null, mouse.x, mouse.y)
            var dx = globalPos.x - startX
            var dy = globalPos.y - startY
            var delta = root.resizeMode === "diagonal"
                ? Math.max(dx, dy)
                : dx
            root.resized(startValue + delta)
            root.resizedXY(dx, dy, startValue)
        }
        onReleased: {
            root.resizeFinished()
        }
    }
}