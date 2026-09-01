import QtQuick
import QtQuick.Effects
import qs.modules.common

RectangularShadow {
    id: root

    required property var target
    property var source: target
    anchors.fill: target

    property real verticalOffset: 1.0
    property real horizontalOffset: 0.0
    property real samples: 9
    property bool transparentBorder: true
    property bool fast: false

    radius: (target && target.radius !== undefined) ? target.radius : 8
    blur: 0.9 * Appearance.sizes.elevationMargin
    offset: Qt.vector2d(horizontalOffset, verticalOffset)
    spread: 1
    color: Appearance.colors.colShadow
    cached: true
    z: -1
}
