import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RippleButton {
    id: root
    required property string materialSymbol
    required property bool current
    property bool showLabel: true
    horizontalPadding: 10

    implicitHeight: 40
    implicitWidth: implicitContentWidth + horizontalPadding * 2
    // rounding.full clamps to the same pill and, unlike height / 2, collapses
    // with the rest of the shell in sharp mode (DESIGN.md 4.1).
    buttonRadius: Appearance.rounding.full

    colBackground: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer)
    // Hand-mixed films, so the alphas are the 3.1 tokens: 0.08 hover, 0.10 press.
    // A current tab keeps no hover film of its own.
    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnSurface, current ? 1 : 0.92)
    colRipple: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.90)

    // ToolbarTabBar paints the selected pill behind this button, so the state
    // film and the content both have to answer to what is underneath.
    readonly property color colContent: root.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
    colStateLayer: root.colContent

    contentItem: Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: 8

        MaterialSymbol {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            iconSize: Appearance.font.pixelSize.huge
            text: root.materialSymbol
            // Selection reads on the icon as a fill, which MaterialSymbol already
            // animates on the effects spec (DESIGN.md 7).
            fill: root.current ? 1 : 0
            color: root.colContent

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
        StyledText {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showLabel
            text: root.text
            // DESIGN.md 9's tab recipe: the label crossfades on elementMoveFast
            // while the indicator behind it moves on a spatial spec.
            color: root.colContent

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}
