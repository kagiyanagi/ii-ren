import qs.modules.common
import qs.modules.common.widgets
import QtQuick

RippleButton {
    id: button

    property string iconName
    property int iconFill: 0
    // Something this button turned on (a recording, the keyboard) is still on.
    property bool active: false
    // Material bar style (bar.barGroupStyle 3): a tonal (secondary container)
    // circle that opens into a primary-container pill under the pointer or
    // while its thing is on.
    property bool material: false
    readonly property bool expanded: button.material && (button.hovered || button.active)

    // 32 is the pointer-shell minimum hit area (DESIGN.md 3.4). The Material
    // circle paints 24 inside it, 4 in from every side, the inset
    // BarMaterialPill keeps its accent at -- the paint shrinks, not the target.
    implicitHeight: 32
    implicitWidth: implicitHeight + (button.expanded ? 24 : 0)
    Behavior on implicitWidth {
        enabled: button.material
        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
    }

    states: State {
        when: button.material
        PropertyChanges {
            target: button
            topInset: 4
            bottomInset: 4
            backgroundBleed: -4
            buttonRadius: Appearance.rounding.full
            colBackground: button.active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
            colBackgroundHover: button.active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer
            colRipple: Appearance.colors.colPrimaryContainerActive
            colStateLayer: Appearance.colors.colOnPrimaryContainer
        }
    }

    contentItem: MaterialSymbol {
        horizontalAlignment: Text.AlignHCenter
        text: button.iconName
        fill: button.iconFill
        iconSize: Appearance.font.pixelSize.large
        color: button.expanded ? Appearance.colors.colOnPrimaryContainer : button.material ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
}
