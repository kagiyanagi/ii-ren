import qs.modules.common.widgets
import qs.modules.common
import QtQuick

Rectangle {
    id: highlightOverlay
    color: Appearance.colors.colSecondaryContainer
    radius: Appearance.rounding.small
    opacity: 0
    z: -1

    function startAnimation() {
        blinkAnimation.start()
    }
    
    component BlinkAnim: NumberAnimation {
        target: highlightOverlay
        property: "opacity"
        duration: Appearance.animation.elementMoveFast.duration
        easing.type: Appearance.animation.elementMoveFast.type
        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
    }

    SequentialAnimation {
        id: blinkAnimation
        loops: 3

        BlinkAnim {
            to: 0.8
        }

        BlinkAnim {
            to: 0
        }
    }
    
}