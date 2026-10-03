import QtQuick
import QtQuick.Effects
import qs.modules.common

RectangularShadow {
    required property var target
    anchors.fill: target
    radius: target.radius ?? 0 // a target without corners (a plain Item) gets square ones
    blur: 0.9 * Appearance.sizes.elevationMargin
    offset: Qt.vector2d(0.0, 1.0)
    spread: 1
    color: Appearance.colors.colShadow
    cached: true
}
