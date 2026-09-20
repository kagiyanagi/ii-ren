import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Material 3 expressive style toolbar.
 * https://m3.material.io/components/toolbars
 */
Item {
    id: root

    property bool enableShadow: true
    property real padding: 8
    property alias colBackground: background.color
    property alias spacing: toolbarLayout.spacing
    default property alias toolbarData: toolbarLayout.data
    implicitWidth: background.implicitWidth
    implicitHeight: background.implicitHeight
    property alias radius: background.radius

    Loader {
        active: root.enableShadow
        anchors.fill: background
        sourceComponent: StyledRectangularShadow {
            target: background
            anchors.fill: undefined
        }
    }

    // A toolbar grows and shrinks as its contents change: that is size, so it
    // rides a spatial spec (DESIGN.md 2.1). It was on elementMoveFast, the
    // effects one, which is the curve for the colour underneath it.
    Behavior on implicitWidth {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    Rectangle {
        id: background
        anchors.fill: parent
        // The semantic token, not the generated palette entry: colSurfaceContainer
        // is solved against the layer below it, so the toolbar stays right when
        // content transparency is on (DESIGN.md 6.1). Identical with it off.
        color: Appearance.colors.colSurfaceContainer
        implicitHeight: 56
        implicitWidth: toolbarLayout.implicitWidth + root.padding * 2
        readonly property int fullRadius: Config.options.appearance.sharpMode ? Appearance.rounding.full : height / 2
        radius: fullRadius

        RowLayout {
            id: toolbarLayout
            spacing: 4
            anchors {
                fill: parent
                margins: root.padding
            }
        }
    }
}
