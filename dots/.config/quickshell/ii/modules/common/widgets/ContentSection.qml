import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property string title
    property string icon: ""
    property string tooltip: ""
    property bool collapsible: false
    property bool expanded: false
    property list<string> stringMap: []
    default property alias contentData: sectionContent.contentData

    readonly property color tintBackground: Appearance.colors.colPrimaryContainer
    readonly property color tintForeground: Appearance.colors.colOnPrimaryContainer

    Layout.fillWidth: true
    spacing: 10

    Component.onCompleted: {
        // `page` is the enclosing ContentPage's id, resolved out of the caller's
        // file scope. 146 of the 177 callers are sub-components that never had
        // one, and a bare reference throws a ReferenceError there rather than
        // skipping registration.
        const ownerPage = (typeof page !== 'undefined') ? page : null
        if (!ownerPage || ownerPage.register == false) return
        // Quick is page 0, so a falsy test left it out of search entirely.
        if (typeof ownerPage.index !== 'number') return
        SearchRegistry.registerSection({
            pageIndex: ownerPage.index,
            title: root.title,
            searchStrings: root.stringMap.slice(),
            yPos: root.y
        })
    }

    SearchHandler {
        searchString: root.title
    }

    // The header is its own Item, not a bare RowLayout: a MouseArea anchored
    // inside a layout is undefined behaviour (Qt says so out loud), and the
    // state film needs to sit behind the row without taking a cell in it.
    Item {
        Layout.fillWidth: true
        // Same as ContentSubsection: a header Item that reports no width leaves
        // the whole section with none, and any cell that is not told to fill
        // collapses to zero.
        implicitWidth: headerRow.implicitWidth
        implicitHeight: headerRow.implicitHeight

        StateOverlay {
            anchors.fill: parent
            visible: root.collapsible
            radius: Appearance.rounding.small
            contentColor: Appearance.colors.colOnLayer0
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
            anchors.leftMargin: 4
            spacing: 12

            Rectangle {
                visible: root.icon.length > 0
                opacity: 1 - highlightOverlay.opacity
                implicitWidth: 40
                implicitHeight: 40
                radius: Appearance.rounding.small
                color: root.tintBackground

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.icon
                    iconSize: Appearance.font.pixelSize.huge
                    fill: 1
                    color: root.tintForeground
                }
            }
            StyledText {
                opacity: 1 - highlightOverlay.opacity
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer0
            }
            MaterialSymbol {
                opacity: 1 - highlightOverlay.opacity
                visible: root.tooltip && root.tooltip.length > 0
                text: "info"
                iconSize: Appearance.font.pixelSize.larger

                color: Appearance.colors.colOnSecondaryContainer
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
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnLayer0
                rotation: root.expanded ? 0 : -90
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                }
            }
        }
    }

    Item {
        Layout.fillWidth: true
        // Both dimensions: a wrapper that reports only a height sizes its
        // section to nothing in the other direction.
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
