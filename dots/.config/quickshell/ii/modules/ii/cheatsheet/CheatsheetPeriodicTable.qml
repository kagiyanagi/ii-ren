pragma ComponentBehavior: Bound

import "periodic_table.js" as PTable
import "elements_theme.js" as ETheme
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    readonly property var elements: PTable.elements
    readonly property bool dark: Appearance.m3colors.darkmode

    property string modeId: "family"
    readonly property var mode: ETheme.modeById(root.modeId)
    readonly property var domain: ETheme.trendDomain(root.elements, root.mode)
    // Density runs from 0.00009 to 22.6; on a linear ramp every element but the
    // heavy metals lands on the same step.
    readonly property bool logarithmic: root.modeId === "density"

    property string query: ""
    property var selected: null

    // 18 groups plus the row label, 7 periods plus the group-label row plus the
    // gap and the two f-block rows.
    readonly property int columns: 19
    readonly property int rows: 11
    readonly property int gap: 4
    // One size that makes the whole table fit whichever axis runs out first.
    readonly property int tileSize: Math.max(28, Math.floor(Math.min(
        (tableArea.width - (root.columns - 1) * root.gap) / root.columns,
        (tableArea.height - (root.rows - 1) * root.gap) / root.rows)))

    implicitWidth: 1100
    implicitHeight: 620

    function matches(element) {
        const q = root.query.trim().toLowerCase();
        if (q.length === 0)
            return true;
        return element.symbol.toLowerCase() === q
            || element.name.toLowerCase().indexOf(q) === 0
            || String(element.number) === q;
    }

    function tileColor(element) {
        if (root.modeId === "family")
            return ETheme.familyColor(element.category, root.dark);
        if (root.modeId === "block")
            return ETheme.blockColor(element.block, root.dark);
        const value = ETheme.trendValue(element, root.mode);
        if (value === null)
            return Appearance.colors.colLayer2;
        return ETheme.trendColor(ETheme.rampStep(value, root.domain.min, root.domain.max, root.logarithmic), root.dark);
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && root.selected !== null) {
            root.selected = null;
            event.accepted = true;
        }
    }


    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // --- toolbar ---------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            MaterialTextField {
                Layout.preferredWidth: 200
                Layout.preferredHeight: 40
                font.pixelSize: Appearance.font.pixelSize.smaller
                placeholderText: Translation.tr("Symbol, name or number")
                text: root.query
                onTextChanged: root.query = text
            }

            StyledText {
                Layout.leftMargin: 4
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: Translation.tr("Colour by")
            }

            ButtonGroup {
                Layout.alignment: Qt.AlignVCenter

                Repeater {
                    model: ETheme.modes
                    delegate: GroupButton {
                        required property var modelData
                        // Sized to its own label: filling the row stretches the
                        // selected pill to a quarter of the toolbar.
                        Layout.fillWidth: false
                        toggled: root.modeId === modelData.id
                        buttonText: modelData.label
                        releaseAction: () => root.modeId = modelData.id
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        // --- the table -------------------------------------------------------
        Item {
            id: tableArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                id: grid
                anchors.centerIn: parent
                implicitWidth: root.columns * root.tileSize + (root.columns - 1) * root.gap
                implicitHeight: root.rows * root.tileSize + (root.rows - 1) * root.gap
                width: implicitWidth
                height: implicitHeight

                function cellX(column) { return column * (root.tileSize + root.gap); }
                function cellY(row) { return row * (root.tileSize + root.gap); }

                Repeater { // group numbers along the top
                    model: 18
                    delegate: StyledText {
                        required property int index
                        x: grid.cellX(index + 1)
                        y: 0
                        width: root.tileSize
                        height: root.tileSize
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        text: index + 1
                    }
                }

                Repeater { // period numbers down the left
                    model: 7
                    delegate: StyledText {
                        required property int index
                        x: 0
                        y: grid.cellY(index + 1)
                        width: root.tileSize
                        height: root.tileSize
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        text: index + 1
                    }
                }

                Repeater {
                    model: root.elements
                    delegate: ElementTile {
                        required property var modelData
                        element: modelData
                        size: root.tileSize
                        // The f block sits on rows 9 and 10 in the source data,
                        // which is the row under the gap.
                        x: grid.cellX(modelData.x)
                        y: grid.cellY(modelData.y)
                        fill: root.tileColor(modelData)
                        dimmed: !root.matches(modelData)
                        onActivated: root.selected = modelData
                    }
                }
            }
        }

        // --- legend ----------------------------------------------------------
        Loader {
            Layout.fillWidth: true
            Layout.preferredHeight: item?.implicitHeight ?? 0
            sourceComponent: root.mode.key === null ? categoricalLegend : rampLegend
        }
    }

    Component {
        id: categoricalLegend
        Flow {
            spacing: 12
            Repeater {
                model: root.modeId === "family" ? ETheme.familyOrder : ETheme.blockOrder
                delegate: Row {
                    id: entry
                    required property var modelData
                    spacing: 6
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: 12
                        implicitHeight: 12
                        radius: Appearance.rounding.verysmall
                        color: root.modeId === "family"
                            ? ETheme.familyColor(entry.modelData, root.dark)
                            : ETheme.blockColor(entry.modelData, root.dark)
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        text: root.modeId === "family" ? entry.modelData : Translation.tr("%1 block").arg(entry.modelData)
                    }
                }
            }
        }
    }

    Component {
        id: rampLegend
        Row {
            spacing: 8
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: root.domain.min === null ? "" : `${root.domain.min} ${root.mode.unit}`
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Repeater {
                    model: 7
                    delegate: Rectangle {
                        required property int index
                        implicitWidth: 28
                        implicitHeight: 12
                        radius: Appearance.rounding.verysmall
                        color: ETheme.trendColor(index, root.dark)
                    }
                }
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: root.domain.max === null ? "" : `${root.domain.max} ${root.mode.unit}`
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: root.logarithmic ? Translation.tr("· log scale · grey = not measured")
                    : Translation.tr("· grey = not measured")
            }
        }
    }

    // --- the detail surface --------------------------------------------------
    ElementDetail {
        id: detail
        anchors.fill: parent
        element: root.selected
        fill: root.selected ? root.tileColor(root.selected) : Appearance.colors.colLayer2
        // The card grows out of the tile that opened it (2.6), so the pivot is
        // that tile's centre mapped into this item.
        originX: root.selected ? grid.mapToItem(root, grid.cellX(root.selected.x) + root.tileSize / 2, 0).x : width / 2
        originY: root.selected ? grid.mapToItem(root, 0, grid.cellY(root.selected.y) + root.tileSize / 2).y : height / 2
        onClosed: root.selected = null
    }
}
