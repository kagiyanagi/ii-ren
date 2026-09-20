pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

SequentialAnimation {
    id: root

    required property Item target
    property real distance: 30

    // A one-shot acknowledgement (DESIGN.md 2.7): it always runs to completion,
    // and it is *meant* to overshoot past `distance` on the way to 0 -- that
    // decay is the shake. No Appearance.animation.* spec is a 5-leg decaying
    // oscillation (they are all two-point tweens), so each leg keeps its own
    // hand-tuned timing rather than being force-fit onto one.
    NumberAnimation { target: root.target; property: "Layout.leftMargin"; to: -root.distance; duration: 50 } // design-ok: see above
    NumberAnimation { target: root.target; property: "Layout.leftMargin"; to: root.distance; duration: 50 } // design-ok: see above
    NumberAnimation { target: root.target; property: "Layout.leftMargin"; to: -root.distance / 2; duration: 40 } // design-ok: see above
    NumberAnimation { target: root.target; property: "Layout.leftMargin"; to: root.distance / 2; duration: 40 } // design-ok: see above
    NumberAnimation { target: root.target; property: "Layout.leftMargin"; to: 0; duration: 30 } // design-ok: see above
}
