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

        // --- toolbar -------------------------------------------------------
        //
        // One strip in one visual language: a tonal search pill and a row of
        // filter chips, all at `rounding.full` on `colLayer2`. Before this the
        // unselected modes were bare labels on no container, so the row read as
        // a sentence of links rather than a control.
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Rectangle { // search
                Layout.preferredWidth: 224
                Layout.preferredHeight: 36
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 4
                    spacing: 8

                    MaterialSymbol {
                        text: "search"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colSubtext
                    }
                    MaterialTextField {
                        id: search
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        // The pill is the container, so the field brings none of
                        // its own -- an outlined box inside a filled pill is two
                        // containers for one control.
                        background: null
                        leftPadding: 0
                        rightPadding: 0
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        placeholderText: Translation.tr("Symbol, name or number")
                        onTextChanged: root.query = text
                    }
                    RippleButton {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        visible: root.query.length > 0
                        buttonRadius: Appearance.rounding.full
                        onClicked: search.clear()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.large
                            text: "close"
                        }

                        StyledToolTip {
                            text: Translation.tr("Clear search")
                        }
                    }
                }
            }

            Flow { // colour-by chips, wrapping rather than overflowing a narrow sheet
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 6

                Repeater {
                    model: ETheme.modes
                    delegate: ModeChip {
                        required property var modelData
                        mode: modelData
                    }
                }
            }
        }

        // --- the table -------------------------------------------------------
        Item {
            id: tableArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                id: grid
                anchors.centerIn: parent
                enabled: root.selected === null
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
                        interactive: root.selected === null
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

    // A filter chip (9): full radius, tonal container when off, `colPrimary`
    // when on, colour on an effects spec.
    component ModeChip: RippleButton {
        id: chip
        required property var mode
        readonly property bool selected: root.modeId === chip.mode.id

        implicitHeight: 36
        buttonRadius: Appearance.rounding.full
        toggled: chip.selected
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        onClicked: root.modeId = chip.mode.id

        contentItem: StyledText {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            leftPadding: 16
            rightPadding: 16
            font.pixelSize: Appearance.font.pixelSize.smaller
            // `chip`, not `parent`: a contentItem is reparented into the
            // control, so `parent` is typed as a bare Item and the two lookups
            // only resolved by luck.
            color: chip.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            text: chip.mode.label
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
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
