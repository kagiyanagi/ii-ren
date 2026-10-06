import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    implicitWidth: gridLayout.implicitWidth
    implicitHeight: gridLayout.implicitHeight
    property bool vertical: false
    property bool invertSide: false
    property bool trayOverflowOpen: false
    property bool showOverflowMenu: true
    property var activeMenu: null

    property list<var> pinnedItems: TrayService.pinnedItems
    property list<var> unpinnedItems: TrayService.unpinnedItems
    onPinnedItemsChanged: updateVisibility()
    onUnpinnedItemsChanged: updateVisibility()

    function updateVisibility() {
        const hasAnyItems = pinnedItems.length > 0 || unpinnedItems.length > 0;
        // `rootItem` is BarComponent's id, and the lock screen uses this tray
        // outside one -- so every tray change while locked threw here and took
        // the overflow close below with it. NetworkSpeed guards the same access.
        if (typeof rootItem !== "undefined")
            rootItem.toggleVisible(hasAnyItems);

        if (unpinnedItems.length === 0) {
            root.closeOverflowMenu();
        }
    }

    function grabFocus() {
        focusGrab.active = true;
    }

    function setExtraWindowAndGrabFocus(window) {
        if (root.activeMenu && root.activeMenu !== window) {
            if (typeof root.activeMenu.close === "function")
                root.activeMenu.close();
            root.activeMenu = null;
        }
        root.activeMenu = window;
        root.grabFocus();
    }

    function releaseFocus() {
        focusGrab.active = false;
    }

    function closeOverflowMenu() {
        focusGrab.active = false;
    }

    onTrayOverflowOpenChanged: {
        if (root.trayOverflowOpen) {
            root.grabFocus();
        }
    }

    HyprlandFocusGrab {
        id: focusGrab
        active: false
        windows: [trayOverflowLayout.QsWindow?.window, root.activeMenu]
        onCleared: {
            root.trayOverflowOpen = false;
            if (root.activeMenu) {
                root.activeMenu.close();
                root.activeMenu = null;
            }
        }
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        anchors.fill: parent
        // The items carry 6px of empty hit area per side now (32px box around a
        // 20px icon), so 4 here lands the same ~16px optical gap on the 4dp grid.
        rowSpacing: 4
        columnSpacing: 4

        RippleButton {
            id: trayOverflowButton
            visible: root.showOverflowMenu && root.unpinnedItems.length > 0
            toggled: root.trayOverflowOpen
            property bool containsMouse: hovered

            downAction: () => root.trayOverflowOpen = !root.trayOverflowOpen

            Layout.fillHeight: !root.vertical
            Layout.fillWidth: root.vertical
            // Hit area to DESIGN 3.4's 32px minimum; the chevron keeps painting
            // at 24 in the middle of it.
            implicitWidth: 32
            implicitHeight: 32
            // Material bar style: the film fills the 32px box, the group pill's
            // own height, so it is concentric with the pill's end.
            background.implicitWidth: Config.options.bar.barGroupStyle === 3 ? 32 : 24
            background.implicitHeight: Config.options.bar.barGroupStyle === 3 ? 32 : 24
            background.anchors.centerIn: this
            colBackgroundToggled: Appearance.colors.colSecondaryContainer
            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
            colRippleToggled: Appearance.colors.colSecondaryContainerActive

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                iconSize: Appearance.font.pixelSize.larger
                text: "expand_more"
                horizontalAlignment: Text.AlignHCenter
                color: root.trayOverflowOpen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                rotation: (root.trayOverflowOpen ? 180 : 0) - (90 * root.vertical) + (180 * root.invertSide)
                // Rotation is spatial, not an effect (DESIGN 2.1), and this is a
                // small widget, so it takes the fast spatial spec.
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                }
            }

            StyledPopup {
                id: overflowPopup
                hoverTarget: trayOverflowButton
                // Not `active`: StyledPopup binds that itself (to its own
                // open/closing state), so overriding it left the window loaded
                // but hidden until the pointer happened to be on the button.
                externalOpen: root.trayOverflowOpen && root.unpinnedItems.length > 0
                // This widget runs its own HyprlandFocusGrab below, and
                // Hyprland honours only one grab per client.
                selfDismiss: false
                // The items already carry 6px of empty hit area, so 4 more puts
                // the icons 10px off the edge instead of 16.
                contentPadding: 4

                GridLayout {
                    id: trayOverflowLayout
                    anchors.centerIn: parent
                    columns: Math.ceil(Math.sqrt(root.unpinnedItems.length))
                    columnSpacing: 4
                    rowSpacing: 4

                    Repeater {
                        model: root.unpinnedItems

                        delegate: SysTrayItem {
                            required property SystemTrayItem modelData
                            item: modelData
                            Layout.fillHeight: !root.vertical
                            Layout.fillWidth: root.vertical
                            onMenuClosed: root.releaseFocus();
                            onMenuOpened: (qsWindow) => root.setExtraWindowAndGrabFocus(qsWindow);
                        }
                    }
                }
            }

            StyledToolTip {
                text: Translation.tr("Show hidden icons")
            }
        }

        Repeater {
            model: ScriptModel {
                values: root.pinnedItems
            }

            delegate: SysTrayItem {
                required property SystemTrayItem modelData
                item: modelData
                Layout.fillHeight: !root.vertical
                Layout.fillWidth: root.vertical
                onMenuClosed: root.releaseFocus();
                onMenuOpened: (qsWindow) => {
                    root.setExtraWindowAndGrabFocus(qsWindow);
                }
            }
        }
    }
}