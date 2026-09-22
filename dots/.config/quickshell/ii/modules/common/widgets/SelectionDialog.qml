import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Item {
    id: root
    property real dialogPadding: 16
    property real dialogMargin: 32
    property string titleText: "Selection Dialog"
    property alias items: choiceModel.values
    property int selectedId: choiceListView.currentIndex
    property var defaultChoice

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
                    currentIndex: root.defaultChoice !== undefined ? root.items.indexOf(root.defaultChoice) : -1
                    spacing: 6

                    model: ScriptModel {
                        id: choiceModel
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
                        checked: index === choiceListView.currentIndex

                        onCheckedChanged: {
                            if (checked) {
                                choiceListView.currentIndex = index;
                            }
                        }
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
                DialogButton {
                    buttonText: Translation.tr("OK")
                    onClicked: root.selected(
                        root.selectedId === -1 ? null :
                        root.items[root.selectedId]
                    )
                }
            }
        }
    }
}
