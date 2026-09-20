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
}
