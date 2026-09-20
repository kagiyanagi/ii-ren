import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property string title: ""
    property string icon: ""
    property string tooltip: ""
    property bool collapsible: false
    property bool expanded: false
    default property alias contentData: sectionContent.contentData

    Layout.fillWidth: true
    // Inset by exactly the card's bleed, so two subsections sharing a ConfigRow
    // end up with the row's gap between their cards instead of overlapping by it.
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    Layout.topMargin: 8
    // Side by side, the shorter one would otherwise centre itself and drop its
    // label below its neighbour's.
    Layout.alignment: Qt.AlignTop
    spacing: 4

    SearchHandler {
        searchString: root.title
    }

    // The header is its own Item, not a bare RowLayout: a MouseArea anchored
    // inside a layout is undefined behaviour (Qt says so out loud), and the
    // state film needs to sit behind the row without taking a cell in it.
    Item {
        Layout.fillWidth: true
        // The subsection's whole implicit width comes from this row, and a
        // `ConfigRow` cell with `Layout.fillWidth: false` is sized by it -- an
        // Item that reports only a height collapses that cell to zero, which
        // stacks its chips in a column and leaves the card a 4px sliver.
        implicitWidth: headerRow.implicitWidth + headerRow.anchors.leftMargin
        // A collapsible header is a hit target and takes 3.4's 32px minimum; a
        // plain label header stays as tall as its text, so the 63 callers that
        // never collapse keep their spacing.
        implicitHeight: root.collapsible ? Math.max(headerRow.implicitHeight, 32) : headerRow.implicitHeight

        StateOverlay {
            anchors.fill: parent
            visible: root.collapsible
            radius: Appearance.rounding.small
            contentColor: Appearance.colors.colOnLayer1
            hover: headerArea.containsMouse
            focused: headerArea.activeFocus
            press: headerArea.pressed
        }

        // Declared before the row so the info icon's own area still wins the
        // pointer: nothing in the row accepts a press, so one falls through.
        MouseArea {
            id: headerArea
            anchors.fill: parent
            visible: root.collapsible
            hoverEnabled: true
            activeFocusOnTab: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
            Keys.onPressed: event => {
                if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) return
                root.expanded = !root.expanded
                event.accepted = true
            }
        }

        RowLayout {
            id: headerRow
            anchors.fill: parent
            anchors.leftMargin: 6

            ContentSubsectionLabel {
                opacity: 1 - highlightOverlay.opacity
                visible: root.title && root.title.length > 0
                text: root.title
            }
            MaterialSymbol {
                opacity: 1 - highlightOverlay.opacity
                visible: root.tooltip && root.tooltip.length > 0
                text: "info"
                iconSize: Appearance.font.pixelSize.large

                color: Appearance.colors.colSubtext
                MouseArea {
                    id: infoMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.WhatsThisCursor
                    StyledToolTip {
                        extraVisibleCondition: false
                        alternativeVisibleCondition: infoMouseArea.containsMouse
                        text: root.tooltip
                    }
                }
            }
            HighlightOverlay {
                id: highlightOverlay
                visible: false
            }
            Item { Layout.fillWidth: true }

            MaterialSymbol {
                visible: root.collapsible
                text: "keyboard_arrow_down"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnLayer1
                rotation: root.expanded ? 0 : -90
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                }
            }
        }
    }

    Item {
        Layout.fillWidth: true
        // The card hugs its chips, so the cell has to ask for their width too --
        // a title is not what decides whether a two-chip row fits on one line.
        implicitWidth: sectionContent.implicitWidth
        implicitHeight: root.expanded || !root.collapsible ? sectionContent.implicitHeight : 0
        visible: root.expanded || !root.collapsible

        ContentGroup {
            id: sectionContent
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
        }
    }
}
