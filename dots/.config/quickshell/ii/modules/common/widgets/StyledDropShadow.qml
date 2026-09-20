import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common

// The non-rectangular half of DESIGN.md 6.2's elevation. RectangularShadow
// draws its shadow from geometry, so it cannot shadow an arc, a polygon or a
// glyph; this one blurs the target's own alpha and costs a live gaussian to do
// it. Reach for StyledRectangularShadow whenever the target is a rounded rect.
DropShadow {
    id: root

    required property var target

    // The blur size, off the same token StyledRectangularShadow renders
    // elevation with. Kept separate from `radius` because `samples` is derived
    // from it: Qt recompiles the blur shader whenever `samples` changes - its
    // own docs say so - and DockAppButton animates `radius` on hover, which
    // through the old `samples: radius * 2 + 1` recompiled it every frame of
    // the animation. Measured on Iris Xe, 26-69% more frames once it stops.
    // A caller that raises `radius` raises `samples` with it, the way
    // OnScreenDisplay does.
    readonly property real elevationBlur: Appearance.sizes.elevationMargin * 0.8

    source: target
    anchors.fill: source
    radius: root.elevationBlur
    samples: Math.ceil(root.elevationBlur) * 2 + 1
    color: Appearance.colors.colShadow
    transparentBorder: true
}
