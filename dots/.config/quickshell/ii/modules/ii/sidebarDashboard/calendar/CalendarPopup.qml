pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// A zero-size pivot at the day's top centre with the card hanging off it. An Item
// scales about its own origin, so the card grows out of the day even when it is
// clamped against the window edge (DESIGN.md 2.6).
Item {
    id: root

    // The day being shown. It stays set through the exit so the card does not empty.
    property CalendarDayButton cell: null
    property real maxWidth
    property var locale
    readonly property int maxRows: 6
    readonly property var events: (cell?.events ?? []).slice().sort((a, b) => (b.allDay ?? false) - (a.allDay ?? false) || a.startDate - b.startDate)
    property bool shown: false

    signal closed

    function show(day: CalendarDayButton): void {
        // BottomWidgetGroup clips, so the card is drawn from the window's content
        // item. Set here, never as a binding: `parent: x.QsWindow?.contentItem`
        // re-evaluates while Quickshell rebuilds the window on every sidebar open,
        // and reparenting mid-rebuild segfaulted the shell.
        const host = day.QsWindow?.contentItem;
        if (!host)
            return;
        root.parent = host;
        root.cell = day;
        if (root.shown)
            return;
        root.shown = true;
        motion.open();
    }

    function hide(): void {
        if (!root.shown)
            return;
        root.shown = false;
        motion.close();
    }

    function timeText(event): string {
        if (event.allDay)
            return Translation.tr("All day");
        const format = Config.options.time.format;
        return `${Qt.formatDateTime(event.startDate, format)} – ${Qt.formatDateTime(event.endDate, format)}`;
    }

    readonly property point anchorPoint: cell && parent ? parent.mapFromItem(cell, cell.width / 2, 0) : Qt.point(0, 0)
    x: anchorPoint.x
    y: anchorPoint.y
    visible: opacity > 0
    opacity: 0
    scale: Appearance.animationCurves.arrowPopupScale

    ArrowPopupMotion {
        id: motion
        target: root
        onClosed: {
            root.cell = null;
            root.closed();
        }
    }

    StyledRectangularShadow {
        target: card
    }

    Rectangle {
        id: card

        readonly property real gutter: Appearance.sizes.elevationMargin
        readonly property real horizontalPadding: 16
        readonly property real verticalPadding: 12

        width: Math.min(root.maxWidth, column.implicitWidth + 2 * horizontalPadding)
        height: column.implicitHeight + 2 * verticalPadding
        x: Math.max(gutter - root.x, Math.min(-width / 2, (root.parent?.width ?? 0) - gutter - width - root.x))
        y: -height - 4
        radius: Appearance.rounding.small
        // Floats over the sidebar rather than sitting on a layer, so the palette
        // colour at full alpha, as DockFolderPopup does.
        readonly property color base: Appearance.m3colors.m3surfaceContainerHigh
        color: Qt.rgba(base.r, base.g, base.b, 1)

        ColumnLayout {
            id: column
            x: card.horizontalPadding
            y: card.verticalPadding
            width: card.width - 2 * card.horizontalPadding
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: root.cell?.date.toLocaleDateString(root.locale, "dddd d MMMM") ?? ""
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnSurface
                elide: Text.ElideRight
            }

            Repeater {
                model: root.events.slice(0, root.maxRows)

                delegate: RowLayout {
                    id: row
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 6
                        implicitWidth: 8
                        implicitHeight: 8
                        radius: Appearance.rounding.full
                        color: row.modelData.color
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.content
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.timeText(row.modelData)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            StyledText {
                visible: root.events.length > root.maxRows
                Layout.leftMargin: 16
                text: Translation.tr("+%1 more").arg(root.events.length - root.maxRows)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }
}
