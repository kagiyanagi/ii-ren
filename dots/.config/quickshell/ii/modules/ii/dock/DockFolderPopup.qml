pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "./widgets"

// The dock's own popups are xdg popups on a layer surface with no keyboard
// focus, so the folder card is its own OnDemand panel instead - that is what
// lets the name at the bottom be typed into, the way the start menu's search is.
Loader {
    id: root

    property Item anchorItem: null
    property var anchorScreen: null
    property int folderIndex: -1

    // Read live rather than passed in, so a rename or a removal shows up in the
    // card that is already open.
    readonly property var folder: TaskbarApps.folders[folderIndex] ?? null
    readonly property var appIds: Array.from(folder?.apps ?? [])

    readonly property string folderName: folder?.name || qsTr("Folder")
    readonly property string dockPos: dock.dockEffectivePosition
    readonly property bool isVertical: dockPos === "left" || dockPos === "right"

    // Button rect in screen coordinates, taken when the card opens: the dock
    // relayouts underneath (apps come and go) and the card shouldn't walk with it.
    property rect anchorRect: Qt.rect(0, 0, 0, 0)

    property bool shown: false
    property bool closing: false
    active: shown || closing

    onFolderChanged: if (root.shown && !root.folder)
        root.close()

    function open(item, index): void {
        root.anchorItem = item;
        root.folderIndex = index;
        const win = item?.QsWindow.window;
        if (!win)
            return;
        const p = item.mapToItem(null, 0, 0);
        // A bottom or right dock's window starts that far into the screen; the
        // other two are anchored at the origin.
        const ox = root.dockPos === "right" ? win.screen.width - win.width : 0;
        const oy = root.dockPos === "bottom" ? win.screen.height - win.height : 0;
        root.anchorRect = Qt.rect(ox + p.x, oy + p.y, item.width, item.height);
        root.anchorScreen = win.screen;
        root.closing = false;
        root.shown = true;
    }

    function close(): void {
        if (!root.shown)
            return;
        // closing first: the loader is kept alive by it, and flipping shown
        // first drops the window mid-click and builds a fresh one right back.
        root.closing = true;
        root.shown = false;
    }

    sourceComponent: PanelWindow {
        id: cardWindow

        screen: root.anchorScreen ?? Quickshell.screens[0]
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:dockFolder"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Connections {
            target: root
            function onShownChanged(): void {
                if (root.shown) {
                    closeAnim.stop();
                    openAnim.restart();
                } else
                    closeAnim.start();
            }
        }

        // Anywhere off the card puts it away, like any other menu.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: root.close()
        }

        StyledRectangularShadow {
            target: card
            scale: card.scale
            transformOrigin: card.transformOrigin
            opacity: card.opacity
        }

        Rectangle {
            id: card

            readonly property real gutter: 8
            readonly property real gap: 10

            x: {
                if (root.dockPos === "left")
                    return root.anchorRect.x + root.anchorRect.width + gap;
                if (root.dockPos === "right")
                    return root.anchorRect.x - width - gap;
                return Math.max(gutter, Math.min(root.anchorRect.x + root.anchorRect.width / 2 - width / 2, cardWindow.width - width - gutter));
            }
            y: {
                if (root.dockPos === "top")
                    return root.anchorRect.y + root.anchorRect.height + gap;
                if (root.dockPos === "bottom")
                    return root.anchorRect.y - height - gap;
                return Math.max(gutter, Math.min(root.anchorRect.y + root.anchorRect.height / 2 - height / 2, cardWindow.height - height - gutter));
            }

            implicitWidth: cardColumn.implicitWidth + 28
            implicitHeight: cardColumn.implicitHeight + 28
            radius: Appearance.rounding.verylarge
            // The semantic colours carry the shell's content transparency, which is
            // for surfaces on a blurred panel - this card floats over the wallpaper
            // and windows, so it takes the palette colour at full alpha, like
            // DockTooltip does.
            readonly property color base: Appearance.m3colors.m3surfaceContainer
            color: Qt.rgba(base.r, base.g, base.b, 1)

            opacity: 0
            scale: 0.5
            transformOrigin: {
                if (root.dockPos === "top")
                    return Item.Top;
                if (root.dockPos === "left")
                    return Item.Left;
                if (root.dockPos === "right")
                    return Item.Right;
                return Item.Bottom;
            }

            // ArrowPopup.animateOpen(), the same numbers the desktop menu pops on.
            ParallelAnimation {
                id: openAnim
                running: true
                SequentialAnimation {
                    NumberAnimation {
                        target: card
                        property: "scale"
                        from: 0.5
                        to: 1.02
                        duration: 200
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                    NumberAnimation {
                        target: card
                        property: "scale"
                        to: 1
                        duration: 200
                        easing.type: Easing.Bezier
                        easing.bezierCurve: [0.3, 0, 0.33, 1, 1, 1]
                    }
                }
                NumberAnimation {
                    target: card
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 83
                }
            }

            ParallelAnimation {
                id: closeAnim
                NumberAnimation {
                    target: card
                    property: "scale"
                    to: 0.5
                    duration: 233
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                }
                SequentialAnimation {
                    PauseAnimation {
                        duration: 150
                    }
                    NumberAnimation {
                        target: card
                        property: "opacity"
                        to: 0
                        duration: 83
                    }
                }
                onFinished: root.closing = false
            }

            // Swallows what the dismiss handler underneath would otherwise take.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            ColumnLayout {
                id: cardColumn
                anchors.centerIn: parent
                spacing: 6

                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape)
                        root.close();
                }

                GridLayout {
                    Layout.alignment: Qt.AlignHCenter
                    // Square-ish, the way a launcher folder lays its pages out.
                    columns: Math.min(4, Math.max(1, Math.ceil(Math.sqrt(root.appIds.length))))
                    rowSpacing: 2
                    columnSpacing: 2

                    Repeater {
                        model: root.appIds

                        delegate: RippleButton {
                            id: appTile
                            required property string modelData

                            readonly property var desktopEntry: TaskbarApps.getCachedDesktopEntry(modelData)

                            implicitWidth: 84
                            implicitHeight: 92
                            padding: 8
                            buttonRadius: Appearance.rounding.normal
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer1Hover
                            colRipple: Appearance.colors.colLayer1Active

                            releaseAction: () => {
                                appTile.desktopEntry?.execute();
                                root.close();
                            }
                            // Right click takes the app back out - the folder itself
                            // goes when the last one leaves.
                            altAction: () => {
                                TaskbarApps.removeFromFolder(root.folderIndex, appTile.modelData);
                                root.close();
                            }

                            contentItem: ColumnLayout {
                                spacing: 4

                                DockIcon {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitWidth: 48
                                    implicitHeight: 48
                                    appId: appTile.modelData
                                    isRunning: true
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: appTile.desktopEntry?.name ?? appTile.modelData
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnSurfaceVariant
                                }
                            }
                        }
                    }
                }

                // The name sits under the apps and is the field itself - click it
                // and type, the way a launcher folder renames.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    // A one-app folder's grid is narrower than its name, and a
                    // field that cannot fit its text scrolls it instead of
                    // centring it - so the name sets the card's width too.
                    implicitWidth: nameField.contentWidth + 20
                    radius: Appearance.rounding.full
                    // Hover is the 0.08 state layer and focus the 0.10 one, which is
                    // what colLayer1Hover and colLayer1Active mix.
                    color: nameField.activeFocus ? Appearance.colors.colLayer1Active : nameHover.hovered ? Appearance.colors.colLayer1Hover : "transparent"

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    StyledTextInput {
                        id: nameField
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        text: root.folderName
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                        selectByMouse: true
                        maximumLength: 40

                        onActiveFocusChanged: if (activeFocus)
                            selectAll()
                        onAccepted: {
                            TaskbarApps.renameFolder(root.folderIndex, text.trim() || root.folderName);
                            focus = false;
                        }
                        onEditingFinished: TaskbarApps.renameFolder(root.folderIndex, text.trim() || root.folderName)
                    }

                    // The field only reads as a field once the pointer says so.
                    // A HoverHandler takes no clicks, so the input still gets them.
                    HoverHandler {
                        id: nameHover
                        cursorShape: Qt.IBeamCursor
                    }
                }
            }
        }
    }
}
