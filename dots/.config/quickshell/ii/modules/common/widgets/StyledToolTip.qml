import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ToolTip {
    id: root
    property bool extraVisibleCondition: true
    property bool alternativeVisibleCondition: false

    // parent is briefly null while a tooltip's owner is still being parented,
    // and the unguarded read threw there. Nothing to hover yet means hidden.
    // A MouseArea reports hover as `containsMouse`, not `hovered`, so the old
    // "no `hovered` property means show it" fallback left every tooltip parented
    // to one permanently on screen. Ask for `containsMouse` before falling back;
    // a parent with neither still shows, which is what the callers that gate on
    // extraVisibleCondition expect.
    readonly property bool internalVisibleCondition: (extraVisibleCondition && parent !== null && (parent.hovered ?? parent.containsMouse ?? true)) || alternativeVisibleCondition
    verticalPadding: 6
    horizontalPadding: 10
    background: null
    font {
        family: Appearance.font.family.main
        variableAxes: Appearance.font.variableAxes.main
        pixelSize: Appearance?.font.pixelSize.smaller ?? 14
        hintingPreference: Font.PreferNoHinting // Prevent shaky text
    }

    // A plain Material tooltip waits out the hover before it appears -- DESIGN.md
    // 9 asks for ~500ms, and with 0 the shell flashed a label at every pointer
    // transit. Verified that Popup honours this with a bound `visible`: the show
    // is deferred, the hide is not, and the binding survives both.
    delay: 500
    visible: internalVisibleCondition

    // Fade only, never a scale (9), and the exit is the faster of the two effects
    // specs (2.5). Without these the QQC2 style animates its own 300ms OutQuad /
    // InQuad in both directions -- symmetric, and not a curve from Appearance.
    enter: Transition {
        NumberAnimation {
            property: "opacity"
            from: 0
            to: 1
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
    }
    exit: Transition {
        NumberAnimation {
            property: "opacity"
            from: 1
            to: 0
            duration: Appearance.animation.elementMoveExit.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
    }

    contentItem: StyledToolTipContent {
        id: contentItem
        font: root.font
        text: root.text
        horizontalPadding: root.horizontalPadding
        verticalPadding: root.verticalPadding
    }
}
