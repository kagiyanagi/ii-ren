pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets
import QtQuick
import Quickshell

/**
 * A lock screen notification list, in Pixel's dress.
 *
 * The look, the arrangement and the gestures are transcribed rather than
 * invented - see NotificationStackCard for the AOSP dimens and
 * NotificationStackView for the stack/shelf model and the swipe thresholds.
 *
 * The one thing that is this file's own problem is input. A session lock
 * surface sits above every layer shell, so a widget drawn on the desktop plane
 * never sees the lock screen's pointer; AbstractBackgroundWidget already solves
 * that for dragging by taking scene coordinates from LockSurface's proxy, and
 * this widget extends the same idea to everything else it responds to. One
 * gesture state machine, driven either by the MouseArea below (desktop) or by
 * the proxy (lock screen), so the two surfaces cannot drift apart.
 *
 * Pointer travel decides who owns a drag: horizontal is a swipe-to-dismiss,
 * mostly-vertical is this widget being moved, and the stack hands the gesture
 * back the moment it decides the travel is not its own. There is nothing to
 * scroll in the stack - the shelf is the overflow - so that split is
 * unambiguous.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "notification_list"
    lockInteractive: true
    hoverEnabled: true
    // Plumbed in by WidgetDelegate, declared per widget rather than on the
    // base, the same way every other widget in this tree takes it.
    property bool wallpaperSafetyTriggered: false

    readonly property var conf: Config.options?.background?.widgets?.notification_list ?? null

    implicitWidth: Math.max(200, root.conf?.width ?? 400)
    implicitHeight: Math.max(1, stack.implicitHeight)

    readonly property bool locked: GlobalStates.screenLocked
    readonly property string privacy: root.conf?.privacy ?? "show"

    // ── Where the notifications come from ────────────────────────────────────
    // The settings app renders widget previews in its own process, so live
    // notifications are gated behind a Loader that never runs there. Deciding
    // on the next event loop pass rather than up front gives the `isPreview`
    // Binding that WidgetsConfig attaches time to land first.
    property bool liveReady: false
    Component.onCompleted: Qt.callLater(() => {
        root.liveReady = !root.isPreview;
    })
    onIsPreviewChanged: root.liveReady = !root.isPreview

    Loader {
        id: liveSource
        active: root.liveReady
        // Synchronous on purpose: an async Loader whose item is the target of a
        // Connections is the segfault in DESIGN.md 2.9.
        asynchronous: false

        sourceComponent: NotificationStackSource {
            onlySinceLock: root.conf?.onlySinceLock ?? false
            sinceTime: root.lockedAt
            showLowUrgency: root.conf?.showLowUrgency ?? true
            skipTransient: root.conf?.skipTransient ?? true
        }
    }

    // "Show seen notifications", off, needs to know when the screen locked.
    property double lockedAt: 0
    onLockedChanged: {
        if (root.locked)
            root.lockedAt = Date.now();
    }

    // Stand-in content for the settings preview, where there is no
    // notification server to ask.
    readonly property var demoGroups: [
        {
            "appName": "Messages",
            "appIcon": "",
            "time": Date.now(),
            "notifications": [
                {
                    "notificationId": -1,
                    "summary": Translation.tr("Ada"),
                    "body": Translation.tr("On my way, five minutes out"),
                    "appName": "Messages",
                    "appIcon": "",
                    "image": "",
                    "urgency": "1",
                    "time": Date.now(),
                    "actions": []
                },
                {
                    "notificationId": -2,
                    "summary": Translation.tr("Rio"),
                    "body": Translation.tr("Sent you the files"),
                    "appName": "Messages",
                    "appIcon": "",
                    "image": "",
                    "urgency": "1",
                    "time": Date.now() - 600000,
                    "actions": []
                }
            ]
        },
        {
            "appName": "Calendar",
            "appIcon": "",
            "time": Date.now() - 1800000,
            "notifications": [
                {
                    "notificationId": -3,
                    "summary": Translation.tr("Standup"),
                    "body": Translation.tr("In 10 minutes · Meeting room 2"),
                    "appName": "Calendar",
                    "appIcon": "",
                    "image": "",
                    "urgency": "1",
                    "time": Date.now() - 1800000,
                    "actions": []
                }
            ]
        }
    ]

    readonly property var sourceGroups: {
        if (!root.liveReady)
            return root.demoGroups;
        if (root.locked && root.privacy === "hideAll")
            return [];
        return liveSource.item?.groups ?? [];
    }

    NotificationStackView {
        id: stack
        width: parent.width
        y: 0

        groups: root.sourceGroups
        view: root.conf?.view ?? "full"
        maxCards: Math.max(1, root.conf?.maxCards ?? 4)
        cardWidth: root.width
        fontScale: Math.max(0.5, (root.conf?.fontScale ?? 100) / 100)
        surfaceOpacity: Math.max(0.05, (root.conf?.backgroundOpacity ?? 100) / 100)
        showActions: root.conf?.showActions ?? true
        showShelf: root.conf?.showShelf ?? true
        dismissOnSwipe: root.conf?.dismissOnSwipe ?? true
        bodyAction: root.conf?.bodyAction ?? "expand"
        // AOSP's public version of a notification: the app and the timestamp
        // stay, the content goes.
        contentHidden: root.locked && root.privacy === "hideContent"
        // An empty stack disappears on the lock screen, the way it does on a
        // phone - but it keeps its placeholder on the desktop, or there would
        // be nothing left to grab and move.
        hideWhenEmpty: (root.conf?.hideWhenEmpty ?? true) && root.locked
        interactive: !root.isPreview
    }

    // ── One gesture state machine, two pointers ──────────────────────────────
    property bool _stackHasGesture: false
    property bool _widgetDragging: false
    property real _pressSceneX: 0
    property real _pressSceneY: 0

    function _toStack(sceneX: real, sceneY: real): point {
        return stack.mapFromItem(null, sceneX, sceneY);
    }

    function _startWidgetDrag(sceneX: real, sceneY: real, ctrl: bool): void {
        if (root.isPreview || root._desktopPositionsLocked)
            return;
        root._widgetDragging = true;
        // Begun from the *original* press point, so a hand-off part way
        // through a gesture does not jump the widget by the travel so far.
        root.beginDragAt(sceneX, sceneY, ctrl);
    }

    function pointerPress(sceneX: real, sceneY: real, button: int, modifiers: int): bool {
        root._pressSceneX = sceneX;
        root._pressSceneY = sceneY;
        root._stackHasGesture = false;
        if (button !== Qt.LeftButton && button !== Qt.MiddleButton)
            return false;
        const p = root._toStack(sceneX, sceneY);
        root._stackHasGesture = stack.beginGesture(p.x, p.y);
        return root._stackHasGesture;
    }

    /** False once the travel says this is the widget being moved, not a swipe. */
    function pointerMove(sceneX: real, sceneY: real): bool {
        if (!root._stackHasGesture)
            return false;
        const p = root._toStack(sceneX, sceneY);
        if (stack.updateGesture(p.x, p.y))
            return true;
        stack.cancelGesture();
        root._stackHasGesture = false;
        return false;
    }

    function pointerRelease(sceneX: real, sceneY: real, button: int): void {
        if (!root._stackHasGesture)
            return;
        const p = root._toStack(sceneX, sceneY);
        stack.endGesture(p.x, p.y, button);
        root._stackHasGesture = false;
    }

    function pointerCancel(): void {
        stack.cancelGesture();
        root._stackHasGesture = false;
    }

    function pointerHover(sceneX: real, sceneY: real): void {
        const p = root._toStack(sceneX, sceneY);
        stack.setHover(p.x, p.y);
    }

    function pointerExit(): void {
        stack.clearHover();
    }

    // Lock screen contract, driven by LockSurface's proxy.
    function lockPointerPress(sceneX: real, sceneY: real, button: int, modifiers: int): bool {
        return root.pointerPress(sceneX, sceneY, button, modifiers);
    }
    function lockPointerMove(sceneX: real, sceneY: real): bool {
        return root.pointerMove(sceneX, sceneY);
    }
    function lockPointerRelease(sceneX: real, sceneY: real, button: int): void {
        root.pointerRelease(sceneX, sceneY, button);
    }
    function lockPointerCancel(): void {
        root.pointerCancel();
    }
    function lockPointerHover(sceneX: real, sceneY: real): void {
        root.pointerHover(sceneX, sceneY);
    }
    function lockPointerExit(): void {
        root.pointerExit();
    }

    // Desktop pointer. Right-click deliberately falls through to the base,
    // which owns the desktop widget menu.
    MouseArea {
        id: pointerLayer
        anchors.fill: parent
        z: 50
        enabled: !root.isPreview
        hoverEnabled: true
        preventStealing: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: {
            if (root._widgetDragging)
                return Qt.ClosedHandCursor;
            if (stack.hoverTarget.length > 0)
                return Qt.PointingHandCursor;
            return root._desktopPositionsLocked ? Qt.ArrowCursor : Qt.OpenHandCursor;
        }

        // A MouseArea with hoverEnabled swallows the hover the base needs to
        // show its resize grip, so hand it back explicitly.
        onEntered: root.contentHovered = true
        onExited: {
            root.contentHovered = false;
            root.pointerExit();
        }

        onPressed: mouse => {
            const p = pointerLayer.mapToItem(null, mouse.x, mouse.y);
            if (root.pointerPress(p.x, p.y, mouse.button, mouse.modifiers))
                return;
            root._startWidgetDrag(p.x, p.y, mouse.modifiers & Qt.ControlModifier);
        }

        onPositionChanged: mouse => {
            const p = pointerLayer.mapToItem(null, mouse.x, mouse.y);
            if (!pointerLayer.pressed) {
                root.pointerHover(p.x, p.y);
                return;
            }
            if (root.pointerMove(p.x, p.y))
                return;
            if (!root._widgetDragging)
                root._startWidgetDrag(root._pressSceneX, root._pressSceneY, mouse.modifiers & Qt.ControlModifier);
            if (root._widgetDragging)
                root.moveDragTo(p.x, p.y, mouse.modifiers & Qt.ControlModifier);
        }

        onReleased: mouse => {
            const p = pointerLayer.mapToItem(null, mouse.x, mouse.y);
            if (root._widgetDragging) {
                root._widgetDragging = false;
                root.endDrag(mouse.modifiers & Qt.ControlModifier);
                return;
            }
            root.pointerRelease(p.x, p.y, mouse.button);
        }

        onCanceled: {
            root.pointerCancel();
            if (root._widgetDragging) {
                root._widgetDragging = false;
                root.cancelDrag();
            }
        }
    }
}
