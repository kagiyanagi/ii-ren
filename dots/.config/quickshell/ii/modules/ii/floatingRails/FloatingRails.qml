pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Controls for every floating window that has none of its own, drawn by the shell:
 * the side rail (windows.floatingControls = "right"), and the top bar whenever
 * hyprbars cannot be loaded -- normally Hyprland draws the top bar itself, see
 * FloatingMode.pluginBars. A layer drawn over the windows can only follow a window a
 * frame behind; the plugin is what makes the bar part of the window.
 *
 * App icon and name at the start, minimize / maximize / close at the end, and the
 * whole strip is the handle the window is dragged by (double-click maximizes, middle
 * click closes, as a caption does). One click-through layer per screen, above the
 * windows. Each rail carves out its own input region, and is cut back to the stretch
 * no window in front covers. Where each window is comes from FloatingMode's
 * in-compositor watcher.
 */
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: railWindow
            required property ShellScreen modelData
            screen: modelData

            WlrLayershell.namespace: "quickshell:floatingRails"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            mask: Region {
                regions: {
                    railRepeater.version;
                    const out = [];
                    for (let i = 0; i < railRepeater.count; i++) {
                        const rail = railRepeater.itemAt(i);
                        if (rail)
                            out.push(rail.region);
                    }
                    return out;
                }
            }

            Repeater {
                id: railRepeater
                // itemAt() notifies nothing; this is what tells the mask a rail came or went.
                property int version: 0
                onItemAdded: version++
                onItemRemoved: version++

                model: ScriptModel {
                    objectProp: "address"
                    values: FloatingMode.rails.filter(r => r.monitor === railWindow.modelData.name)
                }
                delegate: WindowRail {
                    screenX: railWindow.modelData.x
                    screenY: railWindow.modelData.y
                }
            }
        }
    }

    component WindowRail: Item {
        id: rail
        required property var modelData
        property real screenX
        property real screenY

        readonly property string address: modelData.address
        readonly property bool focused: modelData.focused
        // A new rail waits out its window's own spring first: Hyprland opens and moves
        // windows on m3DefaultSpatial, the curve elementMove is fitted to, so appearing
        // at once would put the rail at a window edge that has not arrived yet.
        property bool settled: false
        readonly property bool shown: settled && !modelData.leaving && !modelData.covered
        property bool dragging: false
        // Only the stretch no window in front covers takes input; the mask item
        // carries no transform or scale (tools/check-mask-regions.py).
        readonly property Region region: Region {
            item: rail.shown ? hit : null
        }

        // Hyprland reports a drag or an edge resize as a new position every watcher
        // tick; chasing each one with a 500ms spring would trail the window, so those
        // are followed directly -- and so is the first step of one, anything shorter
        // than the bar is thick: springing that first step left the bar standing for
        // four frames (40px, measured at 60fps) while a Super+drag pulled away. What
        // is left is a real jump -- a keyboard move, maximize -- which Hyprland
        // animates, so the bar springs there on the same curve the window uses.
        property bool tracking: false
        property var memo: ({
                                x: NaN,
                                y: NaN,
                                w: NaN,
                                h: NaN,
                                at: 0
                            })
        readonly property var place: {
            const nx = rail.modelData.x - rail.screenX, ny = rail.modelData.y - rail.screenY;
            const nw = rail.modelData.w, nh = rail.modelData.h;
            const m = rail.memo;
            if (nx !== m.x || ny !== m.y || nw !== m.w || nh !== m.h) {
                const now = Date.now();
                const jump = Math.max(Math.abs(nx - m.x), Math.abs(ny - m.y), Math.abs(nw - m.w), Math.abs(nh - m.h));
                rail.tracking = rail.dragging || now - m.at < 3 * FloatingMode.tickMs || !(jump >= FloatingMode.railWidth);
                m.x = nx;
                m.y = ny;
                m.w = nw;
                m.h = nh;
                m.at = now;
            }
            return {
                x: nx,
                y: ny,
                w: nw,
                h: nh
            };
        }
        readonly property bool horizontal: FloatingMode.railSide === "top"
        // How long the strip is, and how thick, whichever way it runs.
        readonly property real length: rail.horizontal ? rail.width : rail.height
        readonly property real thickness: rail.horizontal ? rail.height : rail.width

        x: rail.place.x
        y: rail.place.y
        width: rail.place.w
        height: rail.place.h

        Behavior on x {
            enabled: !rail.tracking
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        Behavior on y {
            enabled: !rail.tracking
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        Behavior on width {
            enabled: !rail.tracking
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        Behavior on height {
            enabled: !rail.tracking
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        Timer {
            running: true
            interval: Appearance.animation.elementMove.duration
            onTriggered: rail.settled = true
        }

        // floatingMode.js says how the outline follows the window's own corners.
        readonly property var outline: FloatingMode.railOutline(rail.width, rail.height).map(p => Qt.point(p.x,
                                                                                                           p.y))

        // The focused window's rail sits a layer up, as Android lifts the focused
        // caption; the rest recede to the background tone. A caption is a bar, and
        // bars take no hover (M3 4.2) -- its buttons do. Only a press or drag shows.
        property color fill: {
            if (dragArea.pressed)
                return rail.focused ? Appearance.colors.colLayer2Active : Appearance.colors.colLayer1Active;
            return rail.focused ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1;
        }
        Behavior on fill {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        readonly property var span: rail.modelData.span
        // How far the notches reach past the strip, into the window's corners.
        readonly property real overhang: FloatingMode.state.rounding + FloatingMode.state.border

        Item {
            id: hit
            x: rail.horizontal ? rail.span.s0 : 0
            y: rail.horizontal ? 0 : rail.span.s0
            width: rail.horizontal ? rail.span.s1 - rail.span.s0 : rail.width
            height: rail.horizontal ? rail.height : rail.span.s1 - rail.span.s0
        }

        // Where a window in front overlaps the strip, the strip is cut back to the
        // part still in the open rather than hidden whole; a scissor, not a layer.
        Item {
            id: clipper
            clip: rail.modelData.clipped
            x: rail.horizontal ? hit.x : -rail.overhang
            y: rail.horizontal ? 0 : hit.y
            width: rail.horizontal ? hit.width : rail.width + rail.overhang
            height: rail.horizontal ? rail.height + rail.overhang : hit.height

            Item {
                id: painted
                x: -clipper.x
                y: -clipper.y
                width: rail.width
                height: rail.height

                property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
                opacity: {
                    painted.fadeSpec = rail.shown ? Appearance.animation.elementMoveFast :
                                                    Appearance.animation.elementMoveExit;
                    return rail.shown ? 1 : 0;
                }
                visible: opacity > 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: painted.fadeSpec.duration
                        easing.type: painted.fadeSpec.type
                        easing.bezierCurve: painted.fadeSpec.bezierCurve
                    }
                }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: -1
                        fillColor: rail.fill
                        PathPolyline {
                            path: rail.outline
                        }
                    }
                }

                // Under the icon and the buttons: the rest of the strip is the handle.
                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    cursorShape: rail.dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor

                    property point pressScene
                    property point pressWindow
                    // Set while a drag waits for a maximized window to come out under the
                    // pointer: the drag goes on from the restored window, not the old box.
                    property size reanchorFrom: Qt.size(-1, -1)

                    function finish() {
                        if (rail.dragging)
                            FloatingMode.endDrag();
                        rail.dragging = false;
                        dragArea.reanchorFrom = Qt.size(-1, -1);
                    }

                    onPressed: event => {
                        if (event.button === Qt.MiddleButton) {
                            FloatingMode.close(rail.address);
                            return;
                        }
                        FloatingMode.focus(rail.address);
                        const w = FloatingMode.windowFor(rail.address);
                        dragArea.pressScene = dragArea.mapToItem(null, event.x, event.y);
                        dragArea.pressWindow = Qt.point(w?.x ?? 0, w?.y ?? 0);
                    }
                    onPositionChanged: event => {
                        if (!(dragArea.pressedButtons & Qt.LeftButton))
                            return;
                        const p = dragArea.mapToItem(null, event.x, event.y);
                        const dx = p.x - dragArea.pressScene.x, dy = p.y - dragArea.pressScene.y;
                        // A click is not a drag until it passes Qt's own threshold (TASTE.md 4.6).
                        if (!rail.dragging && Math.hypot(dx, dy) < Qt.styleHints.startDragDistance)
                            return;
                        const w = FloatingMode.windowFor(rail.address);
                        if (!rail.dragging && rail.modelData.maximized && w) {
                            dragArea.reanchorFrom = Qt.size(w.w, w.h);
                            FloatingMode.beforeDrag(rail.address);
                        }
                        rail.dragging = true;
                        if (dragArea.reanchorFrom.width >= 0) {
                            if (!w || (w.w === dragArea.reanchorFrom.width && w.h === dragArea.reanchorFrom.height))
                                return;
                            dragArea.reanchorFrom = Qt.size(-1, -1);
                            dragArea.pressScene = p;
                            dragArea.pressWindow = Qt.point(w.x, w.y);
                            return;
                        }
                        FloatingMode.dragTo(rail.address, dragArea.pressWindow.x + dx, dragArea.pressWindow.y
                                            + dy);

                    }
                    onReleased: dragArea.finish()
                    onCanceled: dragArea.finish()
                    onDoubleClicked: event => {
                        if (event.button === Qt.LeftButton)
                            FloatingMode.toggleMaximize(rail.address);
                    }
                }

                // The caption's app icon, the size of a button, inset so it sits square
                // across the strip. It gives way before the buttons do on a small window.
                IconImage {
                    id: appIcon
                    x: rail.horizontal ? inset : (parent.width - implicitSize) / 2
                    y: rail.horizontal ? (parent.height - implicitSize) / 2 : inset
                    readonly property real inset: (rail.thickness - implicitSize) / 2
                    implicitSize: FloatingMode.buttonSize
                    visible: rail.length >= (rail.horizontal ? controls.width : controls.height)
                             + implicitSize * 2
                    source: Quickshell.iconPath(TaskbarApps.getCachedIcon(rail.modelData.cls),
                                                "image-missing")
                }

                // The app's name beside its icon, as Android's caption chip has it. A side
                // rail has no room for a line of text, so it is the bar's alone.
                StyledText {
                    visible: rail.horizontal && appIcon.visible
                    anchors {
                        left: appIcon.right
                        leftMargin: 8
                        right: controls.left
                        rightMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                    text: TaskbarApps.getCachedDesktopEntry(rail.modelData.cls)?.name ?? rail.modelData.cls
                }

                // FloatingMode's button size and gap, the same as the hyprbars bar; minimize, maximize, close in the order Android's caption has them.
                // Short of room, minimize and maximize go first and close stays.
                Grid {
                    id: controls
                    readonly property real inset: (rail.thickness - FloatingMode.buttonSize) / 2
                    readonly property bool roomy: rail.length >= 3 * FloatingMode.buttonSize + 2 * FloatingMode.buttonGap + 2 * inset
                    x: rail.horizontal ? parent.width - width - inset : (parent.width - width) / 2
                    y: rail.horizontal ? (parent.height - height) / 2 : parent.height - height - inset
                    flow: rail.horizontal ? Grid.LeftToRight : Grid.TopToBottom
                    rows: rail.horizontal ? 1 : 3
                    columns: rail.horizontal ? 3 : 1
                    spacing: FloatingMode.buttonGap

                    RailButton {
                        visible: controls.roomy
                        railFocused: rail.focused
                        glyph: "minimize"
                        tip: Translation.tr("Minimize")
                        onClicked: FloatingMode.minimize(rail.address)
                    }
                    RailButton {
                        visible: controls.roomy
                        railFocused: rail.focused
                        glyph: "maximize"
                        tip: rail.modelData.maximized ? Translation.tr("Restore") : Translation.tr("Maximize")
                        onClicked: FloatingMode.toggleMaximize(rail.address)
                    }
                    RailButton {
                        railFocused: rail.focused
                        glyph: "close"
                        tip: Translation.tr("Close")
                        onClicked: FloatingMode.close(rail.address)
                    }
                }
            }
        }
    }

    // The same controls hyprbars.patch strokes on the top bar: a chevron (minimize), a diamond
    // (maximize) and a cross (close), 1.5px strokes on a glyph 3/8 of the button, centred by
    // construction, as the apps with their own buttons draw theirs. Each sits on a chip one
    // layer up from its rail; close hovers in the error container.
    component RailButton: RippleButton {
        id: button
        property string glyph
        property string tip
        property bool railFocused
        readonly property bool closes: button.glyph === "close"
        readonly property real g: button.width * 0.375 / 2

        implicitWidth: FloatingMode.buttonSize
        implicitHeight: FloatingMode.buttonSize
        buttonRadius: Appearance.rounding.full
        colBackground: button.railFocused ? Appearance.colors.colLayer3 : Appearance.colors.colLayer2
        colBackgroundHover: button.closes ? Appearance.colors.colErrorContainer :
                            button.railFocused ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer2Hover
        colRipple: button.closes ? Appearance.colors.colErrorContainerActive :
                   button.railFocused ? Appearance.colors.colLayer3Active : Appearance.colors.colLayer2Active

        contentItem: Shape {
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: button.closes && button.hovered ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
                strokeWidth: 1.5
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathMultiline {
                    readonly property real c: button.width / 2
                    readonly property real g: button.g
                    readonly property real x: button.g * 0.85
                    paths: button.glyph === "minimize" ? [[Qt.point(c - g, c - g / 2), Qt.point(c, c + g / 2), Qt.point(c + g, c - g / 2)]]
                         : button.glyph === "maximize" ? [[Qt.point(c, c - g), Qt.point(c + g, c), Qt.point(c, c + g), Qt.point(c - g, c), Qt.point(c, c - g)]]
                         : [[Qt.point(c - x, c - x), Qt.point(c + x, c + x)], [Qt.point(c + x, c - x), Qt.point(c - x, c + x)]]
                }
            }
        }

        StyledToolTip {
            text: button.tip
        }
    }
}
