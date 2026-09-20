import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets.animations

TriggerAnimation {
    id: root

    property Item targetPlaceholder
    property bool rotateToRight: true

    // The swing settles here, not on targetPlaceholder.iconWidget.rotation
    // directly. That property already carries PagePlaceholder's own
    // `shown`-driven binding (plus the iconSpec side effect that switches its
    // Behavior between enter/exit specs) -- a PropertyAnimation with an
    // external target/property pair is a plain value write, and any such
    // write permanently clears whatever binding was on that property the
    // first time it fires (DESIGN.md 2.9, 10.4 -- the same shape as `Behavior
    // on scale` on top of a `scale:` binding, just via animation.restart()
    // instead of a Behavior). After that, PagePlaceholder's `shown` toggling
    // stops rotating the icon for good.
    //
    // Composing an offset here instead keeps that binding alive forever; it
    // costs PagePlaceholder one line to add `+ openingAnimation.iconRotationOffset`
    // to its own rotation expression so the swing is visible again -- see
    // .audit/cw-motion/notes.md, filed there rather than edited here since
    // PagePlaceholder belongs to cw-scaffolding.
    property real iconRotationOffset: 0

    animation: SequentialAnimation {
        ParallelAnimation {
            // reseting text values to where they should be
            PropertyAction { targets: [targetPlaceholder.titleWidget, targetPlaceholder.descriptionWidget]; property: "opacity"; value: 0 }
            PropertyAction { targets: [targetPlaceholder.titleWidget, targetPlaceholder.descriptionWidget]; property: "Layout.topMargin"; value: -40 }

            // swinging the icon right/left and settling back to 0 -- a delta
            // composed on top of iconWidget.rotation, never written to it.
            PropertyAnimation {
                id: rotationAnim
                target: root; property: "iconRotationOffset"
                to: 0
                duration: Appearance.animation.elementMoveSmall.duration
                easing.type: Appearance.animation.elementMoveSmall.type
                easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
            }

            // scaling the icon widget
            BounceAnimation {
                target: targetPlaceholder.iconWidget
                propertyName: "scale"
            }
        }

        // sliding the texts under the icon
        ParallelAnimation {
            FadeSlide { target: targetPlaceholder.titleWidget }
            FadeSlide { target: targetPlaceholder.descriptionWidget; delay: 50 }
        }
    }

    onTriggerChanged: {
        if (returnOnTrue && trigger || !returnOnTrue && !trigger) return
        if (animation) {
            // we have to set this dynamically (dont ask me the reason behind it)
            rotationAnim.from = root.rotateToRight ? -50 : 50
            animation.restart()
        }
    }

    component FadeSlide: ParallelAnimation {
        id: animRoot
        property var target
        property int delay: 0
        property real fromY: -40

        PropertyAnimation {
            target: animRoot.target; property: "opacity"; from: 0; to: 1
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
        DelayedPropertyAnimation {
            target: animRoot.target; property: "Layout.topMargin"; from: animRoot.fromY; to: 0
            duration: Appearance.animation.elementMoveSmall.duration
            easing.type: Appearance.animation.elementMoveSmall.type
            easing.bezierCurve: Appearance.animation.elementMoveSmall.bezierCurve
            delay: animRoot.delay
        }
    }
}