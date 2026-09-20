import qs.modules.common
import QtQuick

Text {
    id: root
    property bool animateChange: false
    property real animationDistanceX: 0
    property real animationDistanceY: 6

    renderType: Text.QtRendering
    verticalAlignment: Text.AlignVCenter
    // A label that outgrows its cell truncates rather than drawing past it
    // (DESIGN.md 10.17). Measured: wrapped text is untouched until its height is
    // capped, and an unconstrained label never elides, so this only reaches the
    // callers that were overflowing. MaterialSymbol opts back out -- a single
    // glyph elides to nothing.
    elide: Text.ElideRight
    property bool shouldUseNumberFont: /^\d+$/.test(root.text)
    property var defaultFont: shouldUseNumberFont ? Appearance.font.family.numbers : Appearance.font.family.main
    
    font {
        hintingPreference: Font.PreferDefaultHinting
        family: defaultFont
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        variableAxes: shouldUseNumberFont ? ({}) : Appearance.font.variableAxes.main
    }
    color: Appearance?.m3colors.m3onBackground ?? "black"
    linkColor: Appearance?.m3colors.m3primary

    // AOSP's AnimatedContent: slide and fade out, swap the text, slide and fade
    // back in. Both halves ride effects specs -- the few px of travel garnish a
    // crossfade rather than moving the label, and opacity may never overshoot
    // (DESIGN.md 2.1). Exit is the faster of the two (2.5).
    component ExitAnim: NumberAnimation {
        target: root
        duration: Appearance.animation.elementMoveExit.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
    }

    component EnterAnim: NumberAnimation {
        target: root
        duration: Appearance.animation.elementMoveFast.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
    }

    // The travel rides a Translate rather than x/y: assigning x/y on an item the
    // parent positions is overridden every layout pass (DESIGN.md 2.9), which is
    // why an anchored or Layout-placed caller only ever saw the fade. It also
    // drops the construction-time x/y this used to animate back to, which went
    // stale the moment the parent moved the label.
    transform: Translate {
        id: swapOffset
    }

    Behavior on text {
        enabled: root.animateChange

        SequentialAnimation {
            alwaysRunToEnd: true
            ParallelAnimation {
                ExitAnim {
                    target: swapOffset
                    property: "x"
                    to: -root.animationDistanceX
                }
                ExitAnim {
                    target: swapOffset
                    property: "y"
                    to: -root.animationDistanceY
                }
                ExitAnim {
                    property: "opacity"
                    to: 0
                }
            }
            PropertyAction {} // Tie the text update to this point (we don't want it to happen during the first slide+fade)
            PropertyAction {
                target: swapOffset
                property: "x"
                value: root.animationDistanceX
            }
            PropertyAction {
                target: swapOffset
                property: "y"
                value: root.animationDistanceY
            }
            ParallelAnimation {
                EnterAnim {
                    target: swapOffset
                    property: "x"
                    to: 0
                }
                EnterAnim {
                    target: swapOffset
                    property: "y"
                    to: 0
                }
                EnterAnim {
                    property: "opacity"
                    to: 1
                }
            }
        }
    }
}
