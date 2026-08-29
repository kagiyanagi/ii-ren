import QtQuick
import QtQuick.Controls
import qs.modules.common

Flickable {
    id: root
    maximumFlickVelocity: 3500
    boundsBehavior: Flickable.DragOverBounds

    property alias touchpadScrollFactor: wheelHandler.touchpadScrollFactor
    property alias mouseScrollFactor: wheelHandler.mouseScrollFactor
    property alias mouseScrollDeltaThreshold: wheelHandler.mouseScrollDeltaThreshold
    property alias scrollTargetY: wheelHandler.scrollTargetY

    ScrollBar.vertical: StyledScrollBar {}

    WheelScrollHandler {
        id: wheelHandler
        flickable: root
        scrollAnim: scrollAnim
    }

    Behavior on contentY {
        NumberAnimation {
            id: scrollAnim
            duration: Appearance.animation.scroll.duration
            easing.type: Appearance.animation.scroll.type
            easing.bezierCurve: Appearance.animation.scroll.bezierCurve
        }
    }

    onContentYChanged: wheelHandler.syncTarget()

    // Android-style stretch overscroll: a uniform scale anchored at the far edge, which is
    // the 1:1 anchor in Android's StretchEffect. Transform only, so no layer, no FBO and no
    // shader -- yScale is 1 at rest, so this costs nothing until something overscrolls.
    contentItem.transform: Scale {
        origin.y: wheelHandler.overscroll < 0 ? root.contentY + root.height : root.contentY
        yScale: 1 + Math.abs(wheelHandler.overscroll) / Math.max(1, root.height)
    }
}
