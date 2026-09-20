import QtQuick
import QtQuick.Controls
import qs.modules.common

Flickable {
    id: root
    maximumFlickVelocity: 3500
    boundsBehavior: Flickable.DragOverBounds

    // A drag past the end stretches as well, instead of translating the content (3.6).
    // `boundsMovement` holds the content still while Qt keeps reporting how far past
    // the bound the drag went, which is the documented hook for a custom overshoot.
    boundsMovement: Flickable.StopAtBounds
    property real dragStretch: root.verticalOvershoot
    Behavior on dragStretch {
        // 1:1 under the finger; only the release springs back.
        enabled: !root.dragging
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    readonly property real totalOverscroll: wheelHandler.overscroll + root.dragStretch

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

    // Android-style stretch overscroll: a uniform scale anchored at the pushed edge, so the
    // far edge is the one that travels, by the whole overscroll distance. Transform only, so
    // no layer, no FBO and no shader -- yScale is 1 at rest, so this costs nothing until
    // something overscrolls.
    contentItem.transform: Scale {
        // Pinned at the edge being pushed (3.6): pushing past the bottom pins the bottom
        // and moves the top, so the content stretches the way the scroll is going. Anchor
        // it at the far edge instead and the content slides *away* from the push -- which
        // is what this did until it was watched at the bottom of a settings page.
        origin.y: root.totalOverscroll < 0 ? root.contentY : root.contentY + root.height
        yScale: 1 + Math.abs(root.totalOverscroll) / Math.max(1, root.height)
    }
}
