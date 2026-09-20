import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.functions

ScrollBar {
    id: root

    policy: ScrollBar.AsNeeded
    topPadding: Appearance.rounding.normal
    bottomPadding: Appearance.rounding.normal
    // `ScrollBar.vertical:` reparents the bar into the Flickable it scrolls, which is
    // where the movement flags live. What QQC2 binds itself, minus the drop: a wheel or
    // a flick shows the bar too, not only the pointer being on it.
    readonly property Flickable host: root.parent as Flickable
    active: (root.host?.movingVertically ?? false) || hovered || pressed

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
