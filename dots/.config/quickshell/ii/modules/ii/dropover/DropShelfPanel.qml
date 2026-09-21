pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: dropoverScope

    // Nothing pointed at a spot on the screen, so the shelf centres itself on the
    // focused monitor and grows out of its own middle. -1 is that "no drop point".
    function openCentred(): void {
        GlobalStates.dropShelfScreen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
        GlobalStates.dropShelfX = -1;
        GlobalStates.dropShelfY = -1;
        GlobalStates.dropShelfOpen = true;
    }

    IpcHandler {
        target: "dropShelf"

        function toggle(): void {
            if (GlobalStates.dropShelfOpen) {
                DropShelf.hide();
                return;
            }
            dropoverScope.openCentred();
        }

        // Lets a script or keybind put something on the shelf without a drag. A
        // shelf that is already open keeps the spot it was opened at.
        function add(path: string): void {
            if (!GlobalStates.dropShelfOpen)
                dropoverScope.openCentred();
            DropShelf.addItems([`file://${path}`]);
        }

        function remove(path: string): void {
            DropShelf.removeItem(path);
        }

        function clear(): void {
            DropShelf.clear();
        }

        function copy(): void {
            DropShelf.copyAll();
        }
    }

    PanelWindow {
        id: root

        // Not `GlobalStates.dropShelfOpen`: that is the request, and binding the
        // surface straight to it deletes the exit animation with no other symptom
        // -- the window is gone on the frame the flag flips and the close plays to
        // nobody. The card's own alpha is what says the surface is still needed.
        visible: (GlobalStates.dropShelfOpen || shelfCard.opacity > 0) && !GlobalStates.screenLocked

        // Pinned to the screen the drop happened on, not to whichever monitor has
        // focus right now: the shelf exists to be used while another window is
        // being clicked, and a live binding moved it out from under the cursor the
        // moment that happened.
        screen: GlobalStates.dropShelfScreen ?? Quickshell.screens[0]
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:dropShelf"
        WlrLayershell.layer: WlrLayer.Overlay
        // OnDemand, not Exclusive: this is the one popup in the shell that is meant
        // to be used while another window holds the keyboard, so it takes focus
        // when the card is clicked and hands it straight back. Escape then works
        // for anyone who has touched the shelf, which is everyone who wants to
        // close it.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        // Full-screen surface with a masked-out card: the shelf grows and shrinks
        // as items come and go, and reconfiguring a layer surface every frame is
        // what makes that stutter. The mask is also why there is no scrim and no
        // outside-click dismiss, against the popup recipe (DESIGN.md 9) -- the
        // window you are dragging into is behind this one.
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        mask: Region {
            item: shelfCard
        }

        StyledRectangularShadow {
            target: shelfCard
            // anchors.fill doesn't follow a scale transform, so without this the
            // shadow sits full size around a card that is still growing.
            scale: shelfCard.scale
            transformOrigin: shelfCard.transformOrigin
            opacity: shelfCard.opacity
            z: -1
        }

        Rectangle {
            id: shelfCard

            readonly property real gutter: 8
            readonly property real padding: 12
            readonly property real tileSize: 96
            readonly property bool centred: GlobalStates.dropShelfX < 0 || GlobalStates.dropShelfY < 0

            // Which half of the placed card the drop point fell in, which is the
            // same question as which corner is nearest it. Asking the card's edge
            // instead -- `x >= dropShelfX` -- agrees everywhere until the gutter
            // clamp bites and is then wrong for the next half a card width, which
            // is a band down every screen edge. check-dropshelf.py sweeps it.
            readonly property bool leftAligned: GlobalStates.dropShelfX <= x + width / 2
            readonly property bool topAligned: GlobalStates.dropShelfY <= y + height / 2

            // Top-left corner at the drop point, slid back inside the screen near
            // an edge, so the card grows downward as files land and the corner it
            // pivots on stays where the drop was.
            x: centred ? (root.width - width) / 2 : Math.max(gutter, Math.min(GlobalStates.dropShelfX, root.width - width - gutter))
            y: centred ? (root.height - height) / 2 : Math.max(gutter, Math.min(GlobalStates.dropShelfY, root.height - height - gutter))

            implicitWidth: 360
            implicitHeight: contentColumn.implicitHeight + 2 * padding
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            // Size is spatial and may overshoot (DESIGN.md 2.1). This was on
            // elementMoveFast, which is an effects spec.
            Behavior on implicitHeight {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }

            // Launcher3 ArrowPopup.setPivotForOpenCloseAnimation(): the card grows
            // out of the corner nearest the drop point. Opened without one, it has
            // no nearest corner and grows out of its middle instead.
            transformOrigin: centred ? Item.Center : leftAligned ? (topAligned ? Item.TopLeft : Item.BottomLeft) : (topAligned ? Item.TopRight : Item.BottomRight)

            // Resting state, so a shelf that survives a close animates from a known
            // one next time rather than from whatever the last close left (2.7).
            opacity: 0
            scale: Appearance.animationCurves.arrowPopupScale

            focus: true
            Keys.onEscapePressed: DropShelf.hide()

            // Dropping onto the shelf itself piles more on rather than replacing.
            DropArea {
                anchors.fill: parent
                keys: ["text/uri-list"]

                onEntered: drag => drag.accepted = drag.hasUrls

                onDropped: drop => {
                    if (!drop.hasUrls) {
                        drop.accepted = false;
                        return;
                    }
                    DropShelf.addItems(drop.urls);
                    drop.acceptProposedAction();
                }
            }

            DragProxy {
                id: shelfDragProxy
            }

            ColumnLayout {
                id: contentColumn
                anchors.fill: parent
                anchors.margins: shelfCard.padding
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        text: Translation.tr("Drop shelf")
                        color: Appearance.colors.colOnLayer0
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("%1 items").arg(DropShelf.items.length)
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        elide: Text.ElideRight
                    }

                    IconToolbarButton {
                        Layout.fillHeight: false
                        implicitHeight: 32
                        text: "close"
                        onClicked: DropShelf.hide()
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: shelfCard.tileSize

                    ListView {
                        // Not StyledListView: that one is vertical by construction
                        // -- a vertical scrollbar, a Behavior on contentY, and
                        // add/remove transitions that move y and slide a leaving
                        // row out by the list's full width. Turned sideways it
                        // animates the wrong axis. The parts that do apply are
                        // below, on the right one.
                        id: shelfList
                        anchors.fill: parent
                        orientation: ListView.Horizontal
                        spacing: 4
                        clip: true
                        model: DropShelf.items
                        boundsBehavior: Flickable.DragOverBounds
                        maximumFlickVelocity: 3500

                        ScrollBar.horizontal: StyledScrollBar {}

                        add: Transition {
                            animations: [
                                Appearance.animation.elementMoveFast.numberAnimation.createObject(this, {
                                    property: "opacity",
                                    from: 0,
                                    to: 1
                                }),
                                Appearance.animation.elementMove.numberAnimation.createObject(this, {
                                    property: "scale",
                                    from: 0,
                                    to: 1
                                })
                            ]
                        }

                        // Leaving is the exit spec and is monotone, so the fade
                        // does not dip past 0 and blank the tile early (2.5).
                        remove: Transition {
                            animations: [
                                Appearance.animation.elementMoveExit.numberAnimation.createObject(this, {
                                    property: "opacity",
                                    to: 0
                                }),
                                Appearance.animation.elementMoveExit.numberAnimation.createObject(this, {
                                    property: "scale",
                                    to: 0
                                })
                            ]
                        }

                        displaced: Transition {
                            animations: [
                                Appearance.animation.elementMove.numberAnimation.createObject(this, {
                                    property: "x"
                                })
                            ]
                        }

                        delegate: DropShelfItem {
                            required property string modelData
                            path: modelData
                            dragProxy: shelfDragProxy
                            implicitWidth: shelfCard.tileSize
                            implicitHeight: shelfCard.tileSize
                        }
                    }

                    PagePlaceholder {
                        shown: DropShelf.items.length === 0
                        icon: "inbox"
                        description: Translation.tr("Drop files here")
                        descriptionHorizontalAlignment: Text.AlignHCenter
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.full
                        buttonText: Translation.tr("Copy")
                        enabled: DropShelf.items.length > 0
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: DropShelf.copyAll()
                    }

                    // Text button, not a second filled one: Copy is what the shelf
                    // is for and has to look it (DESIGN.md 3.5).
                    RippleButton {
                        implicitHeight: 40
                        buttonRadius: Appearance.rounding.full
                        buttonText: Translation.tr("Clear")
                        enabled: DropShelf.items.length > 0
                        onClicked: DropShelf.clear()
                    }
                }
            }
        }

        // ArrowPopup.animateOpen() / animateClose(), from the one composite the
        // whole shell shares (DESIGN.md 9, .audit/DECISIONS.md 14). The card owns
        // the transformOrigin, because that is the per-surface half of the recipe.
        ArrowPopupMotion {
            id: motion
            target: shelfCard
        }

        Connections {
            target: GlobalStates

            function onDropShelfOpenChanged(): void {
                if (GlobalStates.dropShelfOpen)
                    motion.open();
                else
                    motion.close();
            }
        }
    }
}
