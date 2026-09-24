import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Item {
    id: root
    property real dialogPadding: 16
    property real dialogMargin: 32
    property string titleText: "Selection Dialog"
    property var items: []
    property var defaultChoice
    // Extra text each item also matches on, keyed by item: an English name for a
    // list of endonyms, say. Shown nowhere.
    property var searchAliases: ({})
    readonly property var filteredItems: {
        const q = root.fold(searchField.text.trim());
        if (q.length === 0) return root.items;
        return root.items.filter(item => root.fold(`${item} ${root.searchAliases[item] ?? ""}`).includes(q));
    }

    // Case and accents folded, so "cestina" finds "Čeština".
    function fold(s) {
        return s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
    }

    signal canceled();
    signal selected(var result);

    Rectangle { // Scrim
        id: scrimOverlay
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: Appearance.colors.colScrim
        MouseArea {
            hoverEnabled: true
            anchors.fill: parent
            preventStealing: true
            propagateComposedEvents: false
        }
    }

    // A dialog sits at elevation 5 (DESIGN.md 6.2), and declared before the
    // surface so it paints behind it.
    StyledRectangularShadow {
        target: dialog
    }

    Rectangle { // The dialog
        id: dialog
        // Layer 2, for the reason WindowDialog spells out: the list card below
        // is `colSurfaceContainerHigh`, which is solved to composite onto
        // `m3surfaceContainer`. Paint the dialog in the colour that token
        // resolves to and the card lands on itself.
        color: Appearance.colors.colLayer2Base
        radius: Appearance.rounding.verylarge
        anchors.fill: parent
        anchors.margins: root.dialogMargin
        implicitHeight: dialogColumnLayout.implicitHeight

        ColumnLayout {
            id: dialogColumnLayout
            anchors.fill: parent
            anchors.margins: root.dialogPadding
            spacing: 16

            WindowDialogTitle {
                id: dialogTitle
                horizontalAlignment: Text.AlignLeft
                text: root.titleText
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: searchField.implicitHeight + 8
                radius: Appearance.rounding.full
                color: Appearance.colors.colSurfaceContainerHigh

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 4
                    spacing: 4

                    MaterialSymbol {
                        Layout.leftMargin: 8
                        text: "search"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colSubtext
                    }

                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Search...")
                        color: Appearance.colors.colOnLayer1
                        placeholderTextColor: Appearance.m3colors.m3outline
                        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer
                        background: null
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.hintingPreference: Font.PreferFullHinting
                        font.variableAxes: Appearance.font.variableAxes.main
                        HoverHandler { cursorShape: Qt.IBeamCursor } // 3.4
                        Component.onCompleted: forceActiveFocus()
                        Keys.onReturnPressed: {
                            if (root.filteredItems.length > 0) root.selected(root.filteredItems[0]);
                        }
                        Keys.onEscapePressed: root.canceled()
                    }

                    RippleButton {
                        visible: searchField.text.length > 0
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackgroundHover: Appearance.colors.colLayer3Hover
                        colBackgroundActive: Appearance.colors.colLayer3Active
                        onClicked: {
                            searchField.text = "";
                            searchField.forceActiveFocus();
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // The list used to be fenced in by a hairline above and below it.
            // DESIGN.md 5.5 replaces those with one card -- whitespace around it,
            // its own rounding, rows clipped to its corners -- which is what the
            // Wi-Fi and Bluetooth dialogs already do. ClippingRectangle, not
            // `clip`: plain clip only clips to the bounding box, so a row's hover
            // fill would square off the corners this rounds.
            ClippingRectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerHigh

                StyledListView {
                    id: choiceListView
                    anchors.fill: parent
                    topMargin: 8
                    bottomMargin: 8
                    spacing: 6
                    Component.onCompleted: positionViewAtIndex(root.items.indexOf(root.defaultChoice), ListView.Center)

                    model: ScriptModel {
                        values: root.filteredItems
                    }

                    delegate: StyledRadioButton {
                        id: radioButton
                        required property var modelData
                        required property int index
                        anchors {
                            left: parent?.left
                            right: parent?.right
                            leftMargin: 12
                            rightMargin: 12
                        }

                        description: modelData.toString()
                        checked: modelData === root.defaultChoice
                        // Tapping a row commits it, as an M3 simple dialog does. A
                        // radio that only marked the row until OK was pressed lost
                        // the choice for anyone who took the tap as the choice.
                        onClicked: root.selected(modelData)
                    }
                }
            }

            WindowDialogButtonRow {
                id: dialogButtonsRowLayout

                Item {
                    Layout.fillWidth: true
                }

                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: root.canceled()
                }
            }
        }
    }
}
