pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks
import qs.modules.waffle.bar

BarPopup {
    id: root

    closeOnFocusLost: false
    onFocusCleared: {
        const hasMenuOpen = (contentItem.children ?? []).some(c => c?.menuOpen);
        if (!hasMenuOpen)
            root.close();
        else
            root.grabFocus();
    }

    contentItem: Item {
        id: contentItem
        anchors.centerIn: parent
        implicitWidth: contentGrid.implicitWidth
        implicitHeight: contentGrid.implicitHeight
        GridLayout {
            id: contentGrid
            anchors.centerIn: parent
            readonly property int unpinnedCount: TrayService.unpinnedItems?.length ?? 0
            rows: Math.max(1, Math.floor(Math.sqrt(Math.max(1, contentGrid.unpinnedCount))))
            columns: Math.max(1, Math.ceil(contentGrid.unpinnedCount / Math.max(1, contentGrid.rows)))
            columnSpacing: 0
            rowSpacing: 0

            Repeater {
                model: ScriptModel {
                    values: TrayService.unpinnedItems ?? []
                    onValuesChanged: {
                        root.updateAnchor();
                        if (values.length === 0) {
                            root.close();
                        }
                    }
                }
                delegate: TrayButton {
                    id: trayButton
                    required property var modelData
                    item: modelData

                    topInset: 0
                    bottomInset: 0
                    implicitWidth: 40
                    implicitHeight: 40

                    colBackground: ColorUtils.transparentize(Looks.colors.bg2)
                    colBackgroundHover: Looks.colors.bg2Hover
                    colBackgroundActive: Looks.colors.bg2Active

                    onMenuOpenChanged: {
                        if (!menuOpen) {
                            root.close();
                        }
                    }

                    property real initialX
                    property real initialY

                    Behavior on x {
                        animation: Looks.transition.move.createObject(this)
                    }
                    Behavior on y {
                        animation: Looks.transition.move.createObject(this)
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        drag.target: parent
                        drag.threshold: 2

                        onPressed: event => {
                            trayButton.Drag.hotSpot.x = event.x;
                            trayButton.Drag.hotSpot.y = event.y;
                            trayButton.initialX = trayButton.x;
                            trayButton.initialY = trayButton.y;
                            trayButton.Drag.active = true;
                        }
                        onReleased: {
                            if (!dragArea.drag.active) {
                                trayButton.click();
                            } else {
                                if (!unpinDropArea.containsDrag && unpinDropArea.willUnpin) {
                                    trayButton.visible = false;
                                    TrayService.togglePin(trayButton.item.id);
                                    unpinDropArea.willUnpin = false;
                                } else {
                                    trayButton.x = trayButton.initialX;
                                    trayButton.y = trayButton.initialY;
                                }
                            }
                            trayButton.Drag.active = false;
                        }
                    }
                }
            }
        }

        DropArea {
            id: unpinDropArea
            anchors.fill: parent
            property bool willUnpin: false
            onEntered: willUnpin = false
            onExited: willUnpin = true
        }
    }
}
