import qs.modules.common
import qs.modules.common.widgets

/**
 * An action pill on a layer-2 Continuity card, one layer up from it. The
 * library default is layer 2, which is the card itself, so a pill had no
 * container until the card was hovered.
 */
RippleButtonWithIcon {
    id: root
    implicitHeight: 32
    buttonRadius: Appearance.rounding.full
    colBackground: Appearance.colors.colLayer3
    colBackgroundHover: Appearance.colors.colLayer3Hover
    colRipple: Appearance.colors.colLayer3Active
    colStateLayer: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
    colText: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
}
