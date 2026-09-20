import QtQuick
import qs.modules.common

// A generic "spring to a peak and settle" -- the shape Appearance.animation.clickBounce
// names ("press feedback springing back"), just applied to whatever property/peak the
// caller wants instead of only a press. It is a one-shot acknowledgement (DESIGN.md 2.7),
// which is why clickBounce's alwaysRunToEnd: true (AnimSpec's own default) is correct here.
SequentialAnimation {
    id: root
    property Item target
    property string propertyName: "scale"
    property real peak: 1.1 // FastBitmapDrawable.HOVERED_SCALE (DESIGN.md 3.3)
    property int totalDuration: Appearance.animation.clickBounce.duration

    NumberAnimation {
        target: root.target
        property: root.propertyName
        to: root.peak
        duration: root.totalDuration / 2
        easing.type: Appearance.animation.clickBounce.type
        easing.bezierCurve: Appearance.animation.clickBounce.bezierCurve
    }
    NumberAnimation {
        target: root.target
        property: root.propertyName
        to: 1
        duration: root.totalDuration / 2
        easing.type: Appearance.animation.clickBounce.type
        easing.bezierCurve: Appearance.animation.clickBounce.bezierCurve
    }
}
