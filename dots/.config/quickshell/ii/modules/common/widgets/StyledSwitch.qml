import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls

/**
 * Material 3 switch. See https://m3.material.io/components/switch/overview
 */
Switch {
    id: root
    property real sizeScale: 0.75 // Default in m3 spec is huge af
    implicitHeight: 32 * root.sizeScale
    implicitWidth: 52 * root.sizeScale
    property color activeColor: Appearance?.colors.colPrimary ?? "#685496"
    property color inactiveColor: Appearance?.colors.colSurfaceContainerHighest ?? "#45464F"

    opacity: root.enabled ? 1 : 0.4 // 3.1: disabled is the whole control, not a grey colour
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    PointingHandInteraction {}

    // Custom track styling
    background: Rectangle {
        width: parent.width
        height: parent.height
        radius: Appearance?.rounding.full ?? 9999
        color: root.checked ? root.activeColor : root.inactiveColor
        border.width: 2 * root.sizeScale
        border.color: root.checked ? root.activeColor : Appearance.m3colors.m3outline

        // 9: track colour on default effects.
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    // Custom thumb styling
    // The handle carries a check/close glyph, so it stays 24dp in both states
    // instead of shrinking to the iconless 16dp thumb. 28dp while pressed is the
    // M3 pressed handle -- this component's squeeze, in the direction the spec
    // gives a switch (a slider's goes the other way).
    indicator: Rectangle {
        width: (root.pressed || root.down) ? (28 * root.sizeScale) : (24 * root.sizeScale)
        height: (root.pressed || root.down) ? (28 * root.sizeScale) : (24 * root.sizeScale)
        radius: Appearance.rounding.full
        color: root.checked ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3outline
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: root.checked ? ((root.pressed || root.down) ? (22 * root.sizeScale) : 24 * root.sizeScale) : ((root.pressed || root.down) ? (2 * root.sizeScale) : 4 * root.sizeScale)

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.checked ? "check" : "close"
            iconSize: 16 * root.sizeScale
            color: root.checked ? Appearance.m3colors.m3onPrimaryContainer : Appearance.m3colors.m3surfaceContainerHighest
        }

        // The handle's state layer, SwitchTokens.StateLayerSize (40dp), which is
        // where hover and the 0.10 focus film live on a switch (3.1). It rides
        // the handle, so it overhangs the 32dp track exactly as M3 draws it.
        StateOverlay {
            anchors.centerIn: parent
            width: 40 * root.sizeScale
            height: 40 * root.sizeScale
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            contentColor: root.checked ? Appearance.m3colors.m3primary : Appearance.m3colors.m3onSurface
            hover: root.hovered
            focused: root.visualFocus
            press: root.down
        }

        // Handle travel and the press squeeze are position and size: fast
        // spatial, the same duration and curve the three hand-written
        // NumberAnimations here used to spell out (2.3, 9).
        Behavior on anchors.leftMargin {
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
        }
        Behavior on width {
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
        }
        Behavior on height {
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
}
