import qs.modules.common
import QtQuick
import QtQuick.Effects

// Repaints whatever it is given in one flat colour, animating between colours.
// The brightness term compensates for the tint's own lightness, so a dark colour
// does not come out muddy the way a plain overlay does.
// The modern replacement for Qt5Compat's ColorOverlay.
MultiEffect {
    id: root

    property color sourceColor: "black"

    colorization: 1
    // MultiEffect's own default here is opaque red, so without this line
    // `sourceColor` only ever set the brightness and every caller came out red.
    colorizationColor: root.sourceColor
    brightness: 1 - root.sourceColor.hslLightness

    Behavior on colorizationColor {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
}
