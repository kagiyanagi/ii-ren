import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

LazyLoader {
    id: root
    property Item hoverTarget
    default property Item contentItem

    readonly property real popupOpenProgress: root.item ? root.item.popupOpenProgress : 0.0

    readonly property real screenWidth: root.item ? root.item.screenWidth : 0
    readonly property real screenHeight: root.item ? root.item.screenHeight : 0
    readonly property bool isScreenSmall: screenHeight > 0 && screenHeight < 800

    readonly property real layoutScale: {
        if (screenHeight <= 0 || !root.contentItem)
            return 1.0;
        var baseScale = Math.max(0.75, Math.min(1.5, screenHeight / 1080.0));
        var barSpace = Config.options.bar.vertical ? 0 : Appearance.sizes.barHeight;
        var maxAllowedHeight = screenHeight - barSpace - Appearance.sizes.elevationMargin * 2 - 40;
        var maxAllowedWidth = (screenWidth > 0 ? screenWidth : 1920) * 0.9;

        var userMultiplier = Config.options?.bar?.tooltips?.popupScaleMultiplier ?? 1.0;
        var scale = baseScale * userMultiplier;
        // Measure with the actual candidate scale. Using baseScale here made
        // the size guard ignore the user multiplier and allowed oversized popup
        // surfaces to exceed the monitor's safe bounds.
        var scaledHeight = (root.contentItem.implicitHeight + root.contentPadding * 2) * scale;
        var scaledWidth = (root.contentItem.implicitWidth + root.contentPadding * 2) * scale;
        if (scaledHeight > maxAllowedHeight) {
            scale = Math.min(scale, Math.max(0.5, maxAllowedHeight / (root.contentItem.implicitHeight + root.contentPadding * 2)));
        }
        if (scaledWidth > maxAllowedWidth) {
            scale = Math.min(scale, Math.max(0.5, maxAllowedWidth / (root.contentItem.implicitWidth + root.contentPadding * 2)));
        }
        return scale;
    }
    property real popupBackgroundMargin: 0
    // Inset between the surface edge and the content.
    property real contentPadding: 10
    // DESIGN.md 9, Popup / context menu: an anchored popup surface is verylarge.
    property int popupRadius: Appearance.rounding.verylarge
    property bool animate: true
    property bool animateHeight: true
    property bool stickyHover: false
    property int keyboardFocus: WlrKeyboardFocus.None

    property bool customPosition: false
    property bool anchorRight: false
    property bool anchorLeft: false
    property bool anchorTop: false
    property bool anchorBottom: false
    property int customMarginLeft: 0
    property int customMarginRight: 0
    property int customMarginTop: 0
    property int customMarginBottom: 0

    // Expose active state to child elements so they can trigger animations,
    // exactly like WeatherPopup does for HourlyForecast.
    readonly property bool opened: _computedActive && !root._isClosing

    property bool _popupHovered: false
    property bool _stickyActive: false
    property bool forceClick: false
    // Set false when the user of this popup runs its own focus grab. Hyprland honours only
    // one grab per client, so a second one silently clears the first.
    property bool selfDismiss: true
    property bool _targetHovered: hoverTarget ? (hoverTarget.containsMouse !== undefined ? hoverTarget.containsMouse : (hoverTarget.hovered !== undefined ? hoverTarget.hovered : false)) : false
    property bool _clickActive: false
    property bool _isClosing: false
    property bool _reopenPending: false

    // Set this and the caller owns whether the popup is open; hover and
    // tooltips.enablePopups are ignored entirely. For popups that are a menu
    // rather than a tooltip - the tray overflow is clicked open and clicked
    // shut, and must not close just because the pointer moved off the button,
    // nor stay open because it is still on it. Leave undefined for the normal
    // hover/click behaviour.
    property var externalOpen: undefined

    // A popup with nothing left in it must not open on hover - an empty card
    // under the pointer reads as a glitch. Defaults true, so only a caller whose
    // every section is config-gated has to say otherwise; `externalOpen` is a
    // deliberate caller decision and overrides it.
    property bool contentAvailable: true

    readonly property bool _computedActive: root.externalOpen !== undefined
        ? root.externalOpen
        : root.contentAvailable && Config.options.bar.tooltips.enablePopups && ((Config.options.bar.tooltips.clickToShow || forceClick) ? _clickActive : (stickyHover ? _stickyActive : (_targetHovered && _openDebounced)))

    property bool _openDebounced: false

    active: _computedActive || _isClosing

    on_ComputedActiveChanged: {
        if (!_computedActive) {
            _isClosing = true;
            _reopenPending = false;
        } else if (_isClosing) {
            // Do not reverse a close halfway through. Child popup animations may
            // still have queued callbacks from the previous entrance; wait for a
            // clean progress=0 reset and reopen the instance afterward.
            _reopenPending = true;
        } else {
            _isClosing = false;
        }
    }

    property QtObject _timers: QtObject {
        property Timer openDebounce: Timer {
            interval: 60
            repeat: false
            onTriggered: {
                if (root._targetHovered && !root._isClosing) {
                    root._openDebounced = true;
                }
            }
        }
        property Timer grace: Timer {
            interval: 100 + Math.max(0, (Config.options && Config.options.bar && Config.options.bar.tooltips && Config.options.bar.tooltips.closeDelay) ? Config.options.bar.tooltips.closeDelay : 0)
            onTriggered: {
                root._popupHovered = false;
                root._stickyActive = false;
            }
        }
        /*
         * The pointer came back while the popup was closing. The re-open cannot
         * ride the same event-loop turn as the close: `active` is
         * `_computedActive || _isClosing`, so clearing _isClosing and setting an
         * open flag together re-evaluates that binding straight back to true and
         * the LazyLoader never tears the instance down - the new popup then
         * inherits the old one's half-finished entrance.
         *
         * What it waits for by name: the DeferredDelete that drops the old
         * window. Qt only delivers that when the event loop unwinds to the level
         * it was posted at, so the shortest real timer is the handle we have on
         * it; Qt.callLater runs too early. It lives on root, not inside the
         * window, so it is not destroyed by the teardown it is waiting for -
         * which is what the 30ms timer that used to sit in there was really for.
         */
        property Timer reopen: Timer {
            interval: 1
            repeat: false
            onTriggered: {
                if (!root._reopenPending)
                    return;

                root._reopenPending = false;
                if (root._targetHovered || Config.options.bar.tooltips.clickToShow || root.forceClick) {
                    if (Config.options.bar.tooltips.clickToShow || root.forceClick)
                        root._clickActive = true;
                    else if (root.stickyHover)
                        root._stickyActive = true;
                    else
                        root._openDebounced = true;
                }
            }
        }
    }

    // Dismiss the popup regardless of which mode opened it (click, sticky hover or plain hover).
    function close() {
        _clickActive = false;
        _stickyActive = false;
        _openDebounced = false;
        _popupHovered = false;
        _timers.openDebounce.stop();
        _timers.grace.stop();
    }

    function _evaluateStickyState() {
        if (!stickyHover)
            return;

        // Neither the popup body nor the source widget may reverse a close in
        // progress. The source widget can request a queued re-open separately.
        if (_isClosing) {
            if (_targetHovered)
                _reopenPending = true;
            return;
        }

        if (_targetHovered || _popupHovered) {
            _stickyActive = true;
            _timers.grace.stop();
        } else if (_stickyActive && !_timers.grace.running) {
            _timers.grace.start();
        }
    }

    function _queueReopenFromTarget() {
        if (!_isClosing || root.forceClick)
            return;

        _timers.grace.stop();
        _reopenPending = true;
    }

    on_TargetHoveredChanged: {
        if (_targetHovered) {
            if (_isClosing)
                _queueReopenFromTarget();
            _timers.openDebounce.restart();
        } else {
            _timers.openDebounce.stop();
            _openDebounced = false;
            _reopenPending = false;
        }

        // forceClick popups are opened and closed by their own onClicked. Hover must not touch
        // them: _clickActive has no unhover path, so a hover-open never closed again.
        if (!root.forceClick) {
            if (Config.options.bar.tooltips.clickToShow) {
                if (_targetHovered && !root._clickActive && !root._isClosing) {
                    root._clickActive = true;
                }
            } else {
                _evaluateStickyState();
            }
        }
    }

    onActiveChanged: {
        if (!active) {
            _popupHovered = false;
            _isClosing = false;
            _openDebounced = false;
            _timers.openDebounce.stop();
            _timers.grace.stop();
        }
    }

    component: PanelWindow {
        id: popupWindow
        WlrLayershell.keyboardFocus: root.keyboardFocus
        color: "transparent"

        readonly property real screenWidth: popupWindow.screen?.width ?? 0
        readonly property real screenHeight: popupWindow.screen?.height ?? 0

        anchors.left: root.customPosition ? root.anchorLeft : (!Config.options.bar.vertical || (Config.options.bar.vertical && !Config.options.bar.bottom))
        anchors.right: root.customPosition ? root.anchorRight : (Config.options.bar.vertical && Config.options.bar.bottom)
        anchors.top: root.customPosition ? root.anchorTop : (Config.options.bar.vertical || (!Config.options.bar.vertical && !Config.options.bar.bottom))
        anchors.bottom: root.customPosition ? root.anchorBottom : (!Config.options.bar.vertical && Config.options.bar.bottom)

        implicitWidth: popupBackground.targetWidth + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin
        implicitHeight: popupBackground._commitHeight + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin

        // The input region must not follow the open animation. popupBackground lives inside
        // animContainer, which carries a Scale transform, and a transform change does not
        // emit the geometry signals Region listens to — so the committed region can stay stuck
        // at the animation's starting offset and swallow clicks aimed at the popup's contents.
        Item {
            id: maskRect
            x: popupBackground.x
            y: popupBackground.y
            width: popupBackground.width
            height: popupBackground.height
        }

        mask: Region {
            item: maskRect
        }

        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        /*
         * The popup wants to sit centred on the bar item that opened it; the
         * screen edge wins when it cannot. Both the wanted position and the one
         * actually used are kept, because their difference is exactly how far
         * the bar item ends up from the surface's centre - which is the
         * open/close pivot (DESIGN.md 2.6). tools/check-popup-pivot.py holds
         * this arithmetic.
         */
        readonly property real anchorIdealLeft: {
            if (!root.hoverTarget || !root.QsWindow)
                return 0;
            const p = root.QsWindow.mapFromItem(root.hoverTarget, 0, 0);
            return p.x + (root.hoverTarget.width - popupWindow.implicitWidth) / 2;
        }
        readonly property real anchorIdealTop: {
            if (!root.hoverTarget || !root.QsWindow)
                return 0;
            const p = root.QsWindow.mapFromItem(root.hoverTarget, 0, 0);
            return p.y + (root.hoverTarget.height - popupWindow.implicitHeight) / 2;
        }
        readonly property real anchorLeftMargin: Math.max(0, Math.min(screenWidth - popupWindow.implicitWidth, anchorIdealLeft))
        readonly property real anchorTopMargin: Math.max(0, Math.min(screenHeight - popupWindow.implicitHeight, anchorIdealTop))

        margins {
            left: {
                if (root.customPosition)
                    return root.customMarginLeft;
                if (!Config.options.bar.vertical)
                    return popupWindow.anchorLeftMargin;
                return Appearance.sizes.verticalBarWidth;
            }

            top: {
                if (root.customPosition)
                    return root.customMarginTop;
                if (!Config.options.bar.vertical)
                    return Appearance.sizes.barHeight;
                return popupWindow.anchorTopMargin;
            }

            right: root.customPosition ? root.customMarginRight : Appearance.sizes.verticalBarWidth
            bottom: root.customPosition ? root.customMarginBottom : Appearance.sizes.barHeight
        }

        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay

        property bool _dismissGrabArmed: false

        HyprlandFocusGrab {
            id: dismissGrab
            windows: [popupWindow]
            active: root.selfDismiss && (Config.options.bar.tooltips.clickToShow || root.forceClick) && root._computedActive && popupWindow._dismissGrabArmed
            onCleared: () => {
                root._clickActive = false;
            }
        }

        // The surface's own open/close transform. Six popups outside this file
        // read popupOpenProgress to time their content entrance and to reset it
        // at exactly 0, so it stays a plain 0..1 ramp riding the same animations.
        property real animProgress: 0.0
        property real surfaceScale: Appearance.animationCurves.arrowPopupScale
        property real surfaceOpacity: 0.0
        readonly property real popupOpenProgress: animProgress

        readonly property bool isBarVertical: Config.options.bar.vertical
        readonly property bool isBarBottom: Config.options.bar.bottom

        /*
         * Origin at the corner nearest the bar item that opened it, in
         * animContainer coordinates - ArrowPopup.setPivotForOpenCloseAnimation().
         * A tray popup grows out of its top-right, one under the clock out of
         * the top-centre, and a bottom bar's grows upward.
         */
        readonly property real pivotX: {
            if (root.customPosition) {
                if (root.anchorLeft)
                    return popupBackground.x;
                if (root.anchorRight)
                    return popupBackground.x + popupBackground.width;
                return popupBackground.x + popupBackground.width / 2;
            }
            if (isBarVertical)
                return isBarBottom ? popupBackground.x + popupBackground.width : popupBackground.x;
            const wanted = popupWindow.anchorIdealLeft + popupWindow.implicitWidth / 2 - popupWindow.anchorLeftMargin;
            return Math.max(popupBackground.x, Math.min(popupBackground.x + popupBackground.width, wanted));
        }
        readonly property real pivotY: {
            if (root.customPosition) {
                if (root.anchorTop)
                    return popupBackground.y;
                if (root.anchorBottom)
                    return popupBackground.y + popupBackground.height;
                return popupBackground.y + popupBackground.height / 2;
            }
            if (!isBarVertical)
                return isBarBottom ? popupBackground.y + popupBackground.height : popupBackground.y;
            const wanted = popupWindow.anchorIdealTop + popupWindow.implicitHeight / 2 - popupWindow.anchorTopMargin;
            return Math.max(popupBackground.y, Math.min(popupBackground.y + popupBackground.height, wanted));
        }

        function resetOpenState(): void {
            popupWindow.animProgress = 0.0;
            popupWindow.surfaceScale = Appearance.animationCurves.arrowPopupScale;
            popupWindow.surfaceOpacity = 0.0;
        }

        // ArrowPopup.animateOpen(), assembled from the transcribed composite
        // (DESIGN.md 9): scale overshoots and settles on its own curve, alpha
        // rides underneath. Same shape DockFolderPopup and DesktopMenu use.
        ParallelAnimation {
            id: openAnim
            SequentialAnimation {
                NumberAnimation {
                    target: popupWindow
                    property: "surfaceScale"
                    from: Appearance.animationCurves.arrowPopupScale
                    to: Appearance.animationCurves.arrowPopupOvershoot
                    duration: Appearance.animationCurves.arrowPopupScaleDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
                NumberAnimation {
                    target: popupWindow
                    property: "surfaceScale"
                    to: 1.0
                    duration: Appearance.animationCurves.arrowPopupScaleDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.arrowPopupSettle
                }
            }
            NumberAnimation {
                target: popupWindow
                property: "surfaceOpacity"
                from: 0.0
                to: 1.0
                duration: Appearance.animationCurves.arrowPopupFadeDuration
            }
            NumberAnimation {
                target: popupWindow
                property: "animProgress"
                from: 0.0
                to: 1.0
                duration: Appearance.animationCurves.arrowPopupScaleDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }

        // ArrowPopup.animateClose(): accelerating, and shorter than the open, so
        // leaving does not feel like entering played backwards (DESIGN.md 2.5).
        ParallelAnimation {
            id: closeAnim
            NumberAnimation {
                target: popupWindow
                property: "surfaceScale"
                to: Appearance.animationCurves.arrowPopupScale
                duration: Appearance.animationCurves.arrowPopupCloseDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: Appearance.animationCurves.arrowPopupFadeHold
                }
                NumberAnimation {
                    target: popupWindow
                    property: "surfaceOpacity"
                    to: 0.0
                    duration: Appearance.animationCurves.arrowPopupFadeDuration
                }
            }
            NumberAnimation {
                target: popupWindow
                property: "animProgress"
                to: 0.0
                duration: Appearance.animationCurves.arrowPopupCloseDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
            }
            onFinished: {
                popupWindow.animProgress = 0.0;
                // Queue before the teardown: clearing _isClosing drops `active`,
                // which destroys this window and everything under it.
                if (root._reopenPending)
                    root._timers.reopen.start();
                root._isClosing = false;
            }
        }

        Connections {
            target: root
            function onActiveChanged() {
                popupWindow.resetOpenState();
                if (root.active)
                    openAnim.start();
            }
            function on_IsClosingChanged() {
                if (root._isClosing) {
                    openAnim.stop();
                    closeAnim.start();
                } else if (root._computedActive) {
                    closeAnim.stop();
                    popupWindow.resetOpenState();
                    openAnim.start();
                }
            }
            function on_ComputedActiveChanged() {
                if (root._computedActive && root.selfDismiss) {
                    popupWindow._dismissGrabArmed = false;
                    dismissGrabArmTimer.restart();
                } else {
                    dismissGrabArmTimer.stop();
                    popupWindow._dismissGrabArmed = false;
                }
            }
        }

        Component.onCompleted: {
            if (root.selfDismiss && Config.options.bar.tooltips.clickToShow) {
                dismissGrabArmTimer.restart();
            }
            popupWindow.resetOpenState();
            openAnim.start();
        }

        Timer {
            id: dismissGrabArmTimer
            interval: 250
            onTriggered: popupWindow._dismissGrabArmed = true
        }

        Item {
            id: animContainer
            anchors.fill: parent
            opacity: popupWindow.surfaceOpacity

            transform: Scale {
                origin.x: popupWindow.pivotX
                origin.y: popupWindow.pivotY
                xScale: popupWindow.surfaceScale
                yScale: popupWindow.surfaceScale
            }

            // Keep the popup vector/text content on the scene graph. Do not put
            // it in an FBO: scaling an FBO pixelates text, Material Symbols,
            // and thin shapes on monitors with fractional scale.
            StyledRectangularShadow {
                target: popupBackground
                visible: !Config.options.appearance.transparency.popups
            }

            Rectangle {
                id: popupBackground
                readonly property real margin: root.contentPadding

                readonly property real targetWidth: ((root.contentItem?.implicitWidth ?? 0) + margin * 2) * root.layoutScale
                readonly property real targetHeight: ((root.contentItem?.implicitHeight ?? 0) + margin * 2) * root.layoutScale

                property bool isVertical: Config.options.bar.vertical
                property bool isBottom: Config.options.bar.bottom
                property int elevation: Appearance.sizes.elevationMargin

                // The height the surface and its window have actually committed
                // to. It trails targetHeight through a Behavior so content that
                // grows or shrinks while the popup is open resizes instead of
                // snapping; during the open/close it is targetHeight exactly,
                // because the surface's own scale is the entrance.
                property real _commitHeight: 0
                property bool _heightReady: false

                onTargetHeightChanged: _commitHeight = targetHeight

                Component.onCompleted: {
                    _commitHeight = targetHeight;
                    Qt.callLater(function () {
                        popupBackground._heightReady = true;
                    });
                }

                Behavior on _commitHeight {
                    enabled: popupBackground._heightReady && root.animate && root.animateHeight
                        && root.opened && popupWindow.animProgress >= 1.0
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                anchors {
                    top: (!isVertical && !isBottom) ? parent.top : undefined
                    bottom: (!isVertical && isBottom) ? parent.bottom : undefined
                    left: (isVertical && !isBottom) ? parent.left : undefined
                    right: (isVertical && isBottom) ? parent.right : undefined

                    topMargin: top ? elevation : undefined
                    bottomMargin: bottom ? elevation : undefined
                    leftMargin: left ? elevation : undefined
                    rightMargin: right ? elevation : undefined

                    verticalCenter: isVertical ? parent.verticalCenter : undefined
                    horizontalCenter: !isVertical ? parent.horizontalCenter : undefined
                }

                width: targetWidth
                height: root.animateHeight ? _commitHeight : targetHeight

                color: Config.options.appearance.transparency.popups ? Appearance.colors.colLayer0 : Appearance.m3colors.m3surfaceContainer
                radius: root.popupRadius
                // Content whose own size is still settling must not paint past
                // the surface while _commitHeight is catching up.
                clip: root._isClosing

                // Escape dismisses, like any other menu (DESIGN.md 9). No
                // `focus: true` here on purpose: popups that take no keyboard
                // focus must not start stealing it, and the ones that do have
                // their own fields that see the key first.
                Keys.onEscapePressed: root.close()

                Item {
                    id: contentContainer
                    anchors.centerIn: parent
                    width: root.contentItem ? root.contentItem.implicitWidth : 0
                    height: root.contentItem ? root.contentItem.implicitHeight : 0

                    // Only the screen-fit scale lives here; the open and close
                    // transform belongs to the whole surface, pivoted on the bar
                    // item, so the content cannot drift away from its card.
                    scale: root.layoutScale
                    transformOrigin: Item.Center
                    clip: false

                    // contentItem is owned by root, which is a LazyLoader (not an Item), so it
                    // outlives this window. Detach it before the window's item tree is torn down,
                    // otherwise it keeps a dangling visual parent and anchors into freed items.
                    Component.onDestruction: {
                        if (!root || !root.contentItem)
                            return;
                        root.contentItem.anchors.fill = undefined;
                        root.contentItem.parent = null;
                    }

                    Component.onCompleted: {
                        if (!root.contentItem)
                            return;
                        root.contentItem.parent = contentContainer;
                        root.contentItem.anchors.centerIn = undefined;
                        root.contentItem.anchors.top = undefined;
                        root.contentItem.anchors.bottom = undefined;
                        root.contentItem.anchors.left = undefined;
                        root.contentItem.anchors.right = undefined;
                        root.contentItem.anchors.fill = contentContainer;
                    }
                }

                HoverHandler {
                    id: popupHoverHandler
                    onHoveredChanged: {
                        root._popupHovered = hovered;
                        root._evaluateStickyState();
                    }
                }

                border.width: Config.options.appearance.transparency.popups ? 0 : 1
                border.color: Appearance.colors.colLayer0Border
            }
        }
    }
}
