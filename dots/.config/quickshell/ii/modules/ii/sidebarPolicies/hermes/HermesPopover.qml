pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * A card that grows out of the control that opened it: Launcher3's ArrowPopup
 * (DESIGN.md §9) on a zero-size pivot at the opener's edge, as CalendarPopup
 * does. An Item scales about its own origin, so the card still grows out of
 * the opener when the clamp shifts it sideways (2.6).
 *
 * Drawn from the window's content item, so the composer's clip cannot slice
 * it. Children go into the card's column.
 */
Item {
    id: root

    /** Above the opener, or below it. */
    property bool opensUp: false
    property real cardWidth: 340
    property real padding: 12
    property bool shown: false
    property alias spacing: column.spacing
    // The panel's rect in the host's coordinates. The window is wider than the
    // panel and masks input to it, so the window's edges are no bound for the card.
    property rect bounds
    default property alias content: column.data

    function open(opener: Item): void {
        // Set here, never as a binding: CalendarPopup found that reparenting
        // while Quickshell rebuilds the window on a sidebar open segfaults.
        const host = opener.QsWindow?.contentItem;
        if (!host)
            return;
        root.parent = host;
        let panel = opener;
        while (panel.parent && panel.parent !== host)
            panel = panel.parent;
        root.bounds = host.mapFromItem(panel, 0, 0, panel.width, panel.height);
        const point = host.mapFromItem(opener, opener.width / 2, root.opensUp ? 0 : opener.height);
        pivot.x = point.x;
        pivot.y = point.y;
        root.shown = true;
        card.forceActiveFocus();
        motion.open();
    }

    function close(): void {
        if (!root.shown)
            return;
        root.shown = false;
        motion.close();
    }

    function toggle(opener: Item): void {
        if (root.shown)
            root.close();
        else
            root.open(opener);
    }

    width: parent?.width ?? 0
    height: parent?.height ?? 0
    // `shown` first: open() focuses the card before the fade has lifted the
    // opacity off 0, and an invisible item cannot take focus, so Escape would
    // fall through to the sidebar and close that instead.
    visible: root.shown || pivot.opacity > 0

    // Closes with the sidebar. A handler on a property rather than a
    // `Connections`: this is built while the page incubates, which is where a
    // `Connections` segfaulted the shell on a reload (QQmlConnections::
    // connectSignalsToMethods, seen twice in this tab).
    readonly property bool panelOpen: GlobalStates.policiesPanelOpen
    onPanelOpenChanged: {
        if (!root.panelOpen)
            root.close();
    }

    MouseArea { // Any press outside dismisses and is consumed; a wheel dismisses and still scrolls
        anchors.fill: parent
        enabled: root.shown
        acceptedButtons: Qt.AllButtons
        onPressed: root.close()
        onWheel: wheel => {
            root.close();
            wheel.accepted = false;
        }
    }

    Item {
        id: pivot
        opacity: 0
        scale: Appearance.animationCurves.arrowPopupScale

        ArrowPopupMotion {
            id: motion
            target: pivot
        }

        StyledRectangularShadow {
            target: card
        }

        Rectangle {
            id: card
            readonly property real gutter: Appearance.sizes.elevationMargin
            readonly property real gap: 4

            width: Math.min(root.cardWidth, root.bounds.width - 2 * gutter)
            height: column.implicitHeight + 2 * root.padding
            // Centred on the opener, then clamped inside the panel.
            x: Math.max(root.bounds.x + gutter - pivot.x, Math.min(-width / 2, root.bounds.x + root.bounds.width - gutter - width - pivot.x))
            y: root.opensUp ? Math.max(root.bounds.y + gutter - pivot.y, -height - gap) : Math.min(gap, root.bounds.y + root.bounds.height - gutter - height - pivot.y)
            radius: Appearance.rounding.verylarge
            // Floats over text rather than sitting on a layer, so the palette
            // colour at full alpha, as CalendarPopup does.
            readonly property color base: Appearance.m3colors.m3surfaceContainerHigh
            color: Qt.rgba(base.r, base.g, base.b, 1)

            Keys.onEscapePressed: root.close()

            MouseArea { // Swallows what the dismiss handler underneath would otherwise take
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            ColumnLayout {
                id: column
                x: root.padding
                y: root.padding
                width: card.width - 2 * root.padding
                spacing: 8
            }
        }
    }
}
