import qs.modules.common
import qs.services
import QtQuick

Item { // Cava audio visualizer
    id: root
    property bool vertical: false
    readonly property bool active: CavaService.active
    readonly property real maxValue: 1000 // cava ascii output range
    property int barCount: 14
    property real barThickness: 3
    property real barSpacing: 3
    readonly property real maxLength: (vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight) * 0.55
    readonly property real span: barCount * (barThickness + barSpacing) - barSpacing

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : span
    implicitHeight: vertical ? span : Appearance.sizes.barHeight

    function levelAt(i) { // loudest of this bar's slice of cava's points, 0..1
        const points = CavaService.visualizerPoints;
        const n = points.length;
        if (!root.active || n === 0) return 0;
        const lo = Math.floor(i * n / root.barCount);
        const hi = Math.max(lo + 1, Math.floor((i + 1) * n / root.barCount));
        return Math.min(Math.max.apply(null, points.slice(lo, hi)) / root.maxValue, 1);
    }

    Grid { // fixed-size cells: audio drives paint, never layout
        anchors.centerIn: parent
        rows: root.vertical ? root.barCount : 1
        columns: root.vertical ? 1 : root.barCount
        spacing: root.barSpacing

        Repeater {
            model: root.barCount
            Item {
                id: cell
                required property int index
                width: root.vertical ? root.maxLength : root.barThickness
                height: root.vertical ? root.barThickness : root.maxLength

                Rectangle {
                    anchors.centerIn: parent
                    readonly property real length: root.barThickness + Math.round(root.levelAt(cell.index) * (root.maxLength - root.barThickness))
                    width: root.vertical ? length : root.barThickness
                    height: root.vertical ? root.barThickness : length
                    radius: root.barThickness / 2
                    color: Appearance.colors.colPrimary
                    opacity: root.active ? 1 : 0.35
                    Behavior on width { enabled: root.vertical; NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
                    Behavior on height { enabled: !root.vertical; NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
                    Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                }
            }
        }
    }
}
