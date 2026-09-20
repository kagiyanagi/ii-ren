import qs.modules.common
import QtQuick
import QtQuick.Layouts

RippleButton { // Expand button
    id: root
    required property int count
    required property bool expanded
    property real fontSize: Appearance.font.pixelSize.small
    property real iconSize: Appearance.font.pixelSize.normal
    implicitHeight: Math.max(32, root.fontSize + 8 * 2)
    implicitWidth: Math.max(root.contentItem.implicitWidth + 8 * 2, 32)
    Layout.alignment: Qt.AlignVCenter
    Layout.fillHeight: false

    buttonRadius: Appearance.rounding.full
    // The group card is layer 2, so a control on it is layer 3. The resting
    // colour used to be a hand-mixed half-hover, which 3.1 forbids and which
    // left nothing between rest and hover to see.
    colBackground: Appearance.colors.colLayer3
    colBackgroundHover: Appearance.colors.colLayer3Hover
    colRipple: Appearance.colors.colLayer3Active
    colStateLayer: Appearance.colors.colOnLayer3

    // Not anchored to the button: a Control positions its own contentItem, and
    // anchoring it as well over-constrains it (10.14). The wrapper carries the
    // implicit size the button measures itself against and centres the row.
    contentItem: Item {
        implicitWidth: contentRow.implicitWidth
        implicitHeight: contentRow.implicitHeight

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: 4

            StyledText {
                Layout.leftMargin: 4
                visible: root.count > 1
                text: root.count
                font.pixelSize: root.fontSize
                color: Appearance.colors.colOnLayer3
            }
            MaterialSymbol {
                text: "keyboard_arrow_down"
                iconSize: root.iconSize
                color: Appearance.colors.colOnLayer3
                rotation: root.expanded ? 180 : 0
                // Rotation is spatial and may overshoot as the chevron flips;
                // elementMoveFast is the effects spec and must not (2.1). One
                // Behavior covers both directions, and elementMoveSmall reverses
                // mid-flight rather than running to the end (2.7).
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                }
            }
        }
    }
}
