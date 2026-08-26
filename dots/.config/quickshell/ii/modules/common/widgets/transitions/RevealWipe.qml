import QtQuick
import Qt5Compat.GraphicalEffects

// Shared OpacityMask reveal wipe. The named transitions (Diamond, Outer,
// Radial, Slash) are thin wrappers that only set the mask geometry and the
// distance metric; TransitionImage loads them by filename, so those names stay.
Item {
    id: effect
    property Item frontImg
    property Item backImg
    property int duration

    property bool hideFront: true
    signal finished()

    // Mask geometry, set by the wrapper.
    property real maskWidth: 200
    property real maskHeight: 200
    property real maskRadius: 0
    property real maskRotation: 0

    // Pick the wipe origin anywhere in the middle half, instead of dead centre.
    property bool randomCenter: true
    // Shrink the mask away instead of growing it (Outer).
    property bool reverse: false
    property bool invert: false

    // (cx, cy) -> final mask scale. Required; each wrapper supplies its metric.
    property var targetScale

    function manhattanMax(cx, cy) {
        return Math.max(cx + cy, (effect.width - cx) + cy, cx + (effect.height - cy), (effect.width - cx) + (effect.height - cy))
    }

    function euclideanMax(cx, cy) {
        return Math.max(Math.hypot(cx, cy), Math.hypot(effect.width - cx, cy), Math.hypot(cx, effect.height - cy), Math.hypot(effect.width - cx, effect.height - cy))
    }

    function start() {
        maskContainer.layer.enabled = true

        let cx = effect.width / 2
        let cy = effect.height / 2
        if (effect.randomCenter) {
            let marginX = effect.width * 0.25
            let marginY = effect.height * 0.25
            cx = marginX + Math.random() * (effect.width - marginX * 2)
            cy = marginY + Math.random() * (effect.height - marginY * 2)
        }
        circleMask.centerX = cx
        circleMask.centerY = cy

        let target = effect.targetScale(cx, cy)
        circleMask.scale = effect.reverse ? target : 0
        wipeMask.visible = true

        revealAnim.from = circleMask.scale
        revealAnim.to = effect.reverse ? 0 : target
        revealAnim.restart()
    }

    function cleanup() {
        wipeMask.visible = false
        circleMask.scale = 0
        maskContainer.layer.enabled = false
    }

    NumberAnimation {
        id: revealAnim
        target: circleMask
        property: "scale"
        duration: effect.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.227, 0.877, 0.959, 0.310, 1.0, 1.0]
        onFinished: effect.finished()
    }

    Item {
        id: maskContainer
        width: effect.width
        height: effect.height
        visible: false
        layer.enabled: false

        Rectangle {
            id: circleMask
            width: effect.maskWidth
            height: effect.maskHeight
            radius: effect.maskRadius
            rotation: effect.maskRotation
            color: "black"
            scale: 0
            transformOrigin: Item.Center

            property real centerX: effect.width / 2
            property real centerY: effect.height / 2

            x: centerX - width / 2
            y: centerY - height / 2
        }
    }

    OpacityMask {
        id: wipeMask
        anchors.fill: parent
        visible: false
        source: effect.frontImg
        maskSource: maskContainer
        invert: effect.invert
    }
}
