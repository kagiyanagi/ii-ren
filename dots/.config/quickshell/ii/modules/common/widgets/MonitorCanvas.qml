pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// Drag-to-arrange view of the displays, scaled to fit whatever they span.
Item {
    id: root

    required property var monitorConfig
    property real padding: 20
    property int selectedIndex: 0
    // Positions shown mid-drag, before anything is committed to the compositor.
    property var previewPositions: ({})
    property bool dragHasOverlap: false

    implicitHeight: 220

    readonly property var bounds: {
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        const mons = root.monitorConfig.monitors;
        for (let i = 0; i < mons.length; i++) {
            const m = mons[i];
            if (m.disabled) continue;
            const px = root.previewPositions[m.name]?.x ?? m.x;
            const py = root.previewPositions[m.name]?.y ?? m.y;
            minX = Math.min(minX, px);
            minY = Math.min(minY, py);
            maxX = Math.max(maxX, px + root.monitorConfig.logicalWidth(m));
            maxY = Math.max(maxY, py + root.monitorConfig.logicalHeight(m));
        }
        if (minX === Infinity)
            return { minX: 0, minY: 0, width: 1920, height: 1080 };
        return { minX: minX, minY: minY, width: maxX - minX, height: maxY - minY };
    }

    readonly property real scaleFactor: {
        if (root.bounds.width === 0 || root.bounds.height === 0) return 0.1;
        return Math.min((canvas.width - root.padding * 2) / root.bounds.width,
                        (canvas.height - root.padding * 2) / root.bounds.height);
    }

    readonly property point offset: Qt.point(
        (canvas.width - root.bounds.width * root.scaleFactor) / 2 - root.bounds.minX * root.scaleFactor,
        (canvas.height - root.bounds.height * root.scaleFactor) / 2 - root.bounds.minY * root.scaleFactor)

    function checkOverlap(monitors: var, idx: int): bool {
        const a = monitors[idx];
        const aw = root.monitorConfig.logicalWidth(a);
        const ah = root.monitorConfig.logicalHeight(a);
        for (let i = 0; i < monitors.length; i++) {
            if (i === idx || monitors[i].disabled) continue;
            const b = monitors[i];
            const bw = root.monitorConfig.logicalWidth(b);
            const bh = root.monitorConfig.logicalHeight(b);
            if (a.x < b.x + bw && a.x + aw > b.x && a.y < b.y + bh && a.y + ah > b.y)
                return true;
        }
        return false;
    }

    // Hyprland wants the layout to start at 0,0, so shift everything back into
    // positive coordinates after a drag that went left or up.
    function computeNormalized(monitors: var, changedIdx: int, newX: int, newY: int): var {
        let m = monitors.map(mon => Object.assign({}, mon));
        m[changedIdx].x = newX;
        m[changedIdx].y = newY;
        let minX = Infinity, minY = Infinity;
        for (let i = 0; i < m.length; i++) {
            if (m[i].disabled) continue;
            minX = Math.min(minX, m[i].x);
            minY = Math.min(minY, m[i].y);
        }
        const offX = minX < 0 ? -minX : 0;
        const offY = minY < 0 ? -minY : 0;
        if (offX > 0 || offY > 0) {
            for (let i = 0; i < m.length; i++) {
                m[i].x += offX;
                m[i].y += offY;
            }
        }
        return m;
    }

    function updatePreview(idx: int, newX: int, newY: int): void {
        const normalized = root.computeNormalized(root.monitorConfig.monitors, idx, newX, newY);
        root.dragHasOverlap = root.checkOverlap(normalized, idx);
        let preview = {};
        for (let i = 0; i < normalized.length; i++)
            preview[normalized[i].name] = { x: normalized[i].x, y: normalized[i].y };
        root.previewPositions = preview;
    }

    function commitPosition(idx: int, newX: int, newY: int): void {
        const normalized = root.computeNormalized(root.monitorConfig.monitors, idx, newX, newY);
        root.monitorConfig.monitors = normalized;
        root.previewPositions = {};
        // Normalizing can shift every display, not just the dragged one.
        for (let i = 0; i < normalized.length; i++)
            root.monitorConfig.applyMonitor(normalized[i]);
        root.monitorConfig.save();
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        Item {
            id: canvas
            anchors.fill: parent

            Repeater {
                model: root.monitorConfig.monitors.length
                delegate: MonitorRect {
                    required property int index
                    monitor: root.monitorConfig.monitors[index]
                    monitorIndex: index
                    monitorConfig: root.monitorConfig
                    scaleFactor: root.scaleFactor
                    canvasOffset: root.offset
                    allMonitors: root.monitorConfig.monitors
                    isSelected: index === root.selectedIndex
                    previewPositions: root.previewPositions
                    hasOverlap: root.dragHasOverlap && isDragging

                    onMonitorClicked: idx => root.selectedIndex = idx
                    onPositionDragging: (idx, x, y) => root.updatePreview(idx, x, y)
                    onPositionCommitted: (idx, x, y) => {
                        const hadOverlap = root.dragHasOverlap;
                        root.previewPositions = {};
                        root.dragHasOverlap = false;
                        // Overlapping displays are a broken layout; drop the drag.
                        if (!hadOverlap)
                            root.commitPosition(idx, x, y);
                    }
                }
            }
        }
    }
}
