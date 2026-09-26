import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * Holds long content at `maxHeight`, with a Show more / Show less under it.
 *
 * A written file, a command's output or a long thought would otherwise fill the
 * sidebar and leave the reply to be scrolled for. It clamps by height, not by
 * lines, because one line of JSON wrapped across forty rows is still one line.
 *
 * No motion of its own: it is meant to sit inside a Revealer, which animates any
 * change in its content's height, so the clip here snaps and the fold around it
 * carries the one motion. Animating here as well would be two for one press. Put
 * it anywhere else and Show more snaps.
 */
Item {
    id: root

    default property alias content: holder.data
    property real maxHeight: 0
    property bool expanded: false
    /** The layer this sits on: the fade ends in it and the button's states are its. */
    property color colBase: Appearance.colors.colLayer4
    property color colHover: Appearance.colors.colLayer4Hover
    property color colActive: Appearance.colors.colLayer4Active

    readonly property real contentHeight: holder.childrenRect.height
    // Only when opening reveals more than the button costs: clamping one line
    // behind a 32px button would take more room than it saves.
    readonly property bool clamped: root.contentHeight > root.maxHeight + moreButton.implicitHeight

    Layout.fillWidth: true
    implicitHeight: viewport.height + (root.clamped ? moreButton.implicitHeight : 0)

    Item {
        id: viewport
        width: root.width
        height: root.clamped && !root.expanded ? root.maxHeight : root.contentHeight
        clip: true

        Item {
            id: holder
            width: parent.width
            height: childrenRect.height
        }

        Rectangle { // Says the text goes on past the clip
            visible: root.clamped && !root.expanded
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: moreButton.implicitHeight
            gradient: Gradient {
                GradientStop { position: 0; color: ColorUtils.transparentize(root.colBase, 1) }
                GradientStop { position: 1; color: root.colBase }
            }
        }
    }

    RippleButton {
        id: moreButton
        visible: root.clamped
        y: viewport.height
        width: root.width
        implicitHeight: 32
        buttonRadius: Appearance.rounding.verysmall
        colBackground: "transparent"
        colBackgroundHover: root.colHover
        colRipple: root.colActive
        onClicked: root.expanded = !root.expanded

        RowLayout {
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.small
                text: root.expanded ? "expand_less" : "expand_more"
                color: Appearance.colors.colSubtext
            }

            StyledText {
                text: root.expanded ? Translation.tr("Show less") : Translation.tr("Show more")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }
}
