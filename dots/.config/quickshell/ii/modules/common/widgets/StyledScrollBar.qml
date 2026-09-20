import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.functions

ScrollBar {
    id: root

    policy: ScrollBar.AsNeeded
    topPadding: Appearance.rounding.normal
    bottomPadding: Appearance.rounding.normal
    active: hovered || pressed

    contentItem: Rectangle {
        implicitWidth: 4
        implicitHeight: root.visualSize
        // full clamps to half the shorter side, and squares off in sharp mode,
        // which width / 2 never did.
        radius: Appearance.rounding.full
        color: Appearance.colors.colOnSurfaceVariant

        opacity: root.policy === ScrollBar.AlwaysOn || (root.active && root.size < 1.0) ? 0.5 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }
}
