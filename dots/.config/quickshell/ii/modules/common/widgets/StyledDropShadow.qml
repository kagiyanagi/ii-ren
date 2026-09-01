import QtQuick
import QtQuick.Effects
import qs.modules.common

RectangularShadow {
    id: root

    required property var target
    property var source: target
    anchors.fill: target
    radius: (target && target.radius !== undefined) ? target.radius : 8
    blur: 0.9 * Appearance.sizes.elevationMargin
    offset: Qt.vector2d(0.0, 1.0)
    spread: 1
    color: Appearance.colors.colShadow
    cached: true
    z: -1
}
