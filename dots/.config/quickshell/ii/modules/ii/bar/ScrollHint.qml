import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Revealer { // Scroll hint
    id: root
    property string icon
    property string side: "left"
    property string tooltipText: ""
    
    MouseArea {
        id: mouseArea
        anchors.right: root.side === "left" ? parent.right : undefined
        anchors.left: root.side === "right" ? parent.left : undefined
        implicitWidth: contentColumn.implicitWidth
        implicitHeight: contentColumn.implicitHeight
        // PopupToolTip reads `parent.hovered`; containsMouse already is that, and
        // it cannot be left stuck true when the revealer collapses under the
        // pointer without an exit event.
        readonly property bool hovered: mouseArea.containsMouse

        hoverEnabled: true
        acceptedButtons: Qt.NoButton

        PopupToolTip {
            extraVisibleCondition: root.tooltipText.length > 0
            text: root.tooltipText
        }

        Column {
            id: contentColumn
            anchors {
                fill: parent
            }
            // Negative: the arrows tuck into the icon's line box, which is taller
            // than the 14px glyph. On the grid (DESIGN.md 5.1).
            spacing: -4
            MaterialSymbol {
                text: "keyboard_arrow_up"
                iconSize: 14
                color: Appearance.colors.colSubtext
            }
            MaterialSymbol {
                text: root.icon
                iconSize: 14
                color: Appearance.colors.colSubtext
            }
            MaterialSymbol {
                text: "keyboard_arrow_down"
                iconSize: 14
                color: Appearance.colors.colSubtext
            }
        }
    }
}