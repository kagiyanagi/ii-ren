pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

MouseArea {
    id: root
    required property SystemTrayItem item

    signal menuOpened(qsWindow: var)
    signal menuClosed()

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    // DESIGN 3.4's 32px minimum hit area on a pointer shell, around DESIGN 5.4's
    // 20px compact icon. IconImage is PreserveAspectFit over min(width, height),
    // so the paint is the same 20px it was when the item was 20 wide and bar-tall.
    readonly property int hitSize: 32
    readonly property int iconSize: 20
    implicitWidth: root.hitSize
    implicitHeight: root.hitSize

    // Launcher3 FastBitmapDrawable: HOVERED_SCALE 1.1 over HOVER_FEEDBACK_DURATION
    // 300ms on emphasizedDecel, with PRESSED_SCALE's squish multiplied in on top so
    // a press still reads on a pointer that was already hovering (DESIGN 3.3).
    // Same composition as DockButton, which is the worked example.
    property real hoverScale: root.containsMouse ? 1.1 : 1.0
    property real pressScale: 1.0

    Behavior on hoverScale {
        NumberAnimation {
            // design-ok: Launcher3 FastBitmapDrawable HOVER_FEEDBACK_DURATION, cited in DESIGN 3.3
            duration: 300
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }

    SequentialAnimation {
        id: bounceAnim
        NumberAnimation {
            target: root
            property: "pressScale"
            to: 0.88
            // design-ok: DockButton's squish-in, kept frame-identical to it
            duration: 90
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "pressScale"
            to: 1.0
            duration: Appearance.animation.clickBounce.duration
            easing.type: Appearance.animation.clickBounce.type
            easing.bezierCurve: Appearance.animation.clickBounce.bezierCurve
        }
    }

    function toggleMenu() {
        if (!root.item.hasMenu)
            return;
        if (!menu.active) {
            menu.open();
            return;
        }
        // The loader now outlives the window by a frame, so a click that lands
        // while the menu is animating shut re-opens it instead of being eaten.
        if (menu.item && menu.item.visible && !menu.item.closing)
            menu.item.close();
        else if (menu.item)
            menu.item.open();
    }

    // The SNI conventions, which are also DESIGN 3.5's: left is the item's primary
    // action, right is its menu, middle its secondary action. An item that says it
    // is menu-only has no primary action to fire, so left opens the menu instead.
    onPressed: event => {
        bounceAnim.restart();
        event.accepted = true;
    }
    onReleased: event => {
        // A release that wandered off the icon is a cancel, not a click.
        if (!root.containsMouse) {
            event.accepted = true;
            return;
        }
        switch (event.button) {
        case Qt.LeftButton:
            if (root.item.onlyMenu)
                root.toggleMenu();
            else
                root.item.activate();
            break;
        case Qt.MiddleButton:
            root.item.secondaryActivate();
            break;
        case Qt.RightButton:
            root.toggleMenu();
            break;
        }
        event.accepted = true;
    }
    onEntered: {
        tooltip.text = TrayService.getTooltipForItem(root.item);
    }

    Loader {
        id: menu
        function open() { menu.active = true; }
        active: false

        sourceComponent: SysTrayMenu {
            Component.onCompleted: this.open();
            trayItemMenuHandle: root.item.menu
            trayItemId: root.item.id

            anchor {
                window: root.QsWindow.window

                rect: {
                    var gap = Appearance.sizes.elevationMargin; // SysTrayItem menu gap
                    var pos = root.mapToItem(null, 0, 0);

                    if (Config.options.bar.vertical) {
                        return Qt.rect(
                            Config.options.bar.bottom ? pos.x - gap : pos.x + gap,
                            pos.y,
                            root.width,
                            root.height
                        );
                    } else {
                        return Qt.rect(
                            pos.x,
                            Config.options.bar.bottom ? pos.y - gap : pos.y + gap,
                            root.width,
                            root.height
                        );
                    }
                }

                edges: {
                    if (Config.options.bar.vertical) {
                        return Config.options.bar.bottom ? (Edges.Left | Edges.Middle) : (Edges.Right | Edges.Middle);
                    } else {
                        return Config.options.bar.bottom ? (Edges.Top | Edges.Center) : (Edges.Bottom | Edges.Center);
                    }
                }

                gravity: {
                    if (Config.options.bar.vertical) {
                        return Config.options.bar.bottom ? Edges.Left : Edges.Right;
                    } else {
                        return Config.options.bar.bottom ? Edges.Top : Edges.Bottom;
                    }
                }
            }

            onMenuOpened: (window) => root.menuOpened(window);
            onMenuClosed: {
                root.menuClosed();
                // menuClosed now arrives from inside the menu's own close
                // animation, so unloading the window here would delete the
                // animation that is still emitting. Let the frame finish first.
                Qt.callLater(() => menu.active = false);
            }
        }
    }

    IconImage {
        id: trayIcon
        source: root.item.icon
        anchors.centerIn: parent
        implicitSize: root.iconSize
        scale: root.hoverScale * root.pressScale

        // Monochrome icons are the tray default, so the old Desaturate +
        // ColorOverlay pair ran two shader passes for every item in the Repeater
        // that builds these (design law 8). MultiEffect does both in one pass:
        // saturation -0.8 is Desaturate's 0.8, colorization 0.1 is the old
        // overlay colour's alpha.
        layer.enabled: Config.options.tray.monochromeIcons
        layer.effect: MultiEffect {
            saturation: -0.8
            colorization: 0.1
            colorizationColor: Appearance.colors.colOnLayer0
        }
    }

    PopupToolTip {
        id: tooltip
        extraVisibleCondition: root.containsMouse
        alternativeVisibleCondition: extraVisibleCondition
        anchorEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top
    }
}
