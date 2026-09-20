pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

RippleButton {
    id: root
    required property QsMenuEntry menuEntry
    property bool forceIconColumn: false
    property bool forceSpecialInteractionColumn: false
    readonly property bool hasIcon: menuEntry.icon.length > 0
    readonly property bool hasSpecialInteraction: menuEntry.buttonType !== QsMenuButtonType.None

    signal dismiss()
    signal openSubmenu(handle: QsMenuHandle)

    // The card under the rows paints the surface; a row only paints its own
    // state films, which RippleButton takes from colLayer1 by default.
    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1, 1)
    // A separator is whitespace on the grid, not a hairline (design law 11).
    // The row stays in the column as an empty spacer so the app's own grouping
    // still reads. `enabled` also carries the app's own greyed-out entries, which
    // RippleButton renders as the 0.4 disabled opacity (DESIGN 3.1).
    enabled: !menuEntry.isSeparator && menuEntry.enabled
    focusPolicy: Qt.StrongFocus

    horizontalPadding: 12
    implicitWidth: menuEntry.isSeparator ? 0 : contentItem.implicitWidth + horizontalPadding * 2
    implicitHeight: menuEntry.isSeparator ? 8 : 36
    Layout.fillWidth: true

    // RippleButton fires its actions from its own MouseArea, so the keyboard has
    // to take the same path. Up/Down walk the column's focus chain, which is in
    // visual order, and wrap inside the menu window (DESIGN 3.7).
    Keys.onUpPressed: root.nextItemInFocusChain(false)?.forceActiveFocus(Qt.TabFocusReason)
    Keys.onDownPressed: root.nextItemInFocusChain(true)?.forceActiveFocus(Qt.TabFocusReason)
    Keys.onRightPressed: if (root.menuEntry.hasChildren) root.releaseAction()
    Keys.onReturnPressed: root.releaseAction()
    Keys.onEnterPressed: root.releaseAction()
    Keys.onSpacePressed: root.releaseAction()

    releaseAction: () => { 
        if (menuEntry.hasChildren) {
            root.openSubmenu(root.menuEntry);
            return;
        }
        menuEntry.triggered();
        root.dismiss(); 
    }
    altAction: (event) => { // Not hog right-click
        event.accepted = false;
    }

    contentItem: RowLayout {
        id: contentItem
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            right: parent.right
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 8
        visible: !root.menuEntry.isSeparator

        // Interaction: checkbox or radio button
        Item {
            visible: root.hasSpecialInteraction || root.forceSpecialInteractionColumn
            implicitWidth: 20
            implicitHeight: 20

            Loader {
                anchors.fill: parent
                active: root.menuEntry.buttonType === QsMenuButtonType.RadioButton

                sourceComponent: StyledRadioButton {
                    enabled: false
                    opacity: 1 // `enabled` is "not interactive" here, not "disabled"
                    padding: 0
                    checked: root.menuEntry.checkState === Qt.Checked
                }
            }

            Loader {
                anchors.fill: parent
                active: root.menuEntry.buttonType === QsMenuButtonType.CheckBox && root.menuEntry.checkState !== Qt.Unchecked

                sourceComponent: MaterialSymbol {
                    text: root.menuEntry.checkState === Qt.PartiallyChecked ? "check_indeterminate_small" : "check"
                    iconSize: 20
                }
            }
        }

        // Button icon
        Item {
            visible: root.hasIcon || root.forceIconColumn
            implicitWidth: 20
            implicitHeight: 20

            Loader {
                anchors.centerIn: parent
                active: root.menuEntry.icon.length > 0
                sourceComponent: IconImage {
                    asynchronous: true
                    source: root.menuEntry.icon
                    implicitSize: 20
                    mipmap: true
                }
            }
        }

        StyledText {
            id: label
            text: root.menuEntry.text
            font.pixelSize: Appearance.font.pixelSize.smallie
            Layout.fillWidth: true
        }

        Loader {
            active: root.menuEntry.hasChildren

            sourceComponent: MaterialSymbol {
                text: "chevron_right"
                iconSize: 20
            }
        }
    }
}
