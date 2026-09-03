pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

/**
 * The lock screen notification stack: cards for what fits, an icon shelf for
 * what does not, and one gesture layer over the lot.
 *
 * Why a Column and not a StyledListView: this is not a scrolling list. Android
 * caps the lock screen at a handful of cards and reduces the rest to icons -
 * NotificationStackSizeCalculator computes a `maxKeyguardNotifications` and
 * pushes "extras [...] into an overflow shelf". The shelf *is* the overflow, so
 * there is nothing to scroll.
 *
 * Why no MouseArea per row: a session lock surface sits above every layer
 * shell, so the widget - which is drawn on the desktop plane - never sees the
 * lock screen's pointer. Everything interactive therefore goes through the
 * functions at the bottom of this file, which take view-local coordinates and
 * are driven either by the widget's own MouseArea (desktop) or by LockSurface's
 * proxy (lock screen). One gesture implementation, two pointers.
 */
Item {
    id: root

    // ── Input ────────────────────────────────────────────────────────────────
    // Ordered newest-app-first, the way the lock screen lists them.
    property var groups: []
    // Android 16's two lock screen views: "full" is its "Full list", "compact"
    // is the default - one notification, the rest as shelf icons.
    property string view: "full"
    property int maxCards: 4
    property real cardWidth: 400
    property real fontScale: 1.0
    property real surfaceOpacity: 1.0
    property bool showActions: true
    property bool showShelf: true
    property bool contentHidden: false
    property bool hideWhenEmpty: false
    property bool interactive: true
    property bool dismissOnSwipe: true
    // What a tap on a card's body does. "expand" is the safe lock screen
    // default; "invoke" fires the notification's default action, which is what
    // tapping does once Android has authenticated you.
    property string bodyAction: "expand"

    signal notificationInvoked(int notificationId, string identifier)

    // ── Metrics ──────────────────────────────────────────────────────────────
    // AOSP `notification_section_divider_height_lockscreen` is 4: the lock
    // screen packs its cards far tighter than the shade's 16.
    readonly property real cardGap: 4
    readonly property bool compactMode: root.view === "compact"

    implicitWidth: root.cardWidth
    implicitHeight: column.implicitHeight

    // ── What is shown as a card, and what falls through to the shelf ─────────
    // Android 16's default lock screen view shows one notification in full and
    // reduces the rest to icons; clicking the shelf raises the cap, and "Full
    // list" starts there.
    property bool shelfExpanded: false
    readonly property int cardBudget: {
        if (root.compactMode)
            return root.shelfExpanded ? root.maxCards : 1;
        return root.maxCards;
    }

    readonly property var cardNames: root.displayNames.slice(0, root.cardBudget)
    readonly property var shelfGroups: {
        if (!root.showShelf)
            return [];
        const out = [];
        const names = root.displayNames.slice(root.cardBudget);
        for (let i = 0; i < names.length; i++) {
            const g = root.groupFor(names[i]);
            if (g)
                out.push(g);
        }
        return out;
    }

    // ── Leaving cards ────────────────────────────────────────────────────────
    // A notification that times out, or that its app takes back, disappears
    // from the service with no warning. Holding the name for one exit animation
    // is the same trick WidgetStateManager plays with `exiting` so a widget has
    // something left to animate out with.
    property var displayNames: []
    property var exitingNames: []
    property var lastGroups: ({})

    function groupFor(name: string): var {
        const live = root.liveByName[name];
        return live !== undefined ? live : root.lastGroups[name];
    }

    readonly property var liveByName: {
        const map = {};
        const list = root.groups ?? [];
        for (let i = 0; i < list.length; i++) {
            if (list[i]?.appName !== undefined)
                map[list[i].appName] = list[i];
        }
        return map;
    }
    readonly property var liveNames: (root.groups ?? []).map(g => g?.appName ?? "").filter(n => n.length > 0)

    onLiveNamesChanged: root._sync()
    Component.onCompleted: root._sync()

    function _sync(): void {
        const live = root.liveNames;
        const previous = root.displayNames;
        const leaving = [];
        const names = live.slice();

        for (let i = 0; i < previous.length; i++) {
            const name = previous[i];
            if (live.indexOf(name) !== -1)
                continue;
            // Already spent its animation on the last pass: let it go now.
            if (root.exitingNames.indexOf(name) !== -1)
                continue;
            leaving.push(name);
            names.splice(Math.min(i, names.length), 0, name);
        }

        const snapshot = {};
        for (let i = 0; i < names.length; i++) {
            const g = root.groupFor(names[i]);
            if (g)
                snapshot[names[i]] = g;
        }

        root.lastGroups = snapshot;
        root.exitingNames = leaving;
        root.displayNames = names;
        if (leaving.length > 0)
            reapTimer.restart();
    }

    Timer {
        id: reapTimer
        // One exit animation (half the enter duration) plus room, then the
        // placeholder goes.
        interval: Math.max(1, Appearance.animation.elementMoveEnter.duration)
        repeat: false
        onTriggered: root._sync()
    }

    // ── Expansion, kept by app name so it survives a delegate rebuild ────────
    property var expandedApps: ({})

    function isExpanded(name: string): bool {
        return root.expandedApps[name] === true;
    }
    function toggleExpanded(name: string): void {
        const next = Object.assign({}, root.expandedApps);
        if (next[name])
            delete next[name];
        else
            next[name] = true;
        root.expandedApps = next;
    }
    function collapseAll(): void {
        root.expandedApps = ({});
        root.shelfExpanded = false;
    }

    // ── Gesture state ────────────────────────────────────────────────────────
    property string hoverTarget: ""
    property int hoverIndex: -1
    property string pressTarget: ""
    property int pressIndex: -1

    // SwipeDismissible's neighbour follow, which is also how Android 16
    // describes it: the alerts next to the one you are dragging "subtly respond
    // to your drag". Self takes the whole distance, ±1 takes 0.3, ±2 takes 0.1.
    property int swipeIndex: -1
    property real swipeDistance: 0
    property bool swipeCommitted: false
    property bool swipeIsChild: false
    property int swipeChildId: -1

    // AOSP SwipeHelper: SWIPED_FAR_ENOUGH_SIZE_FRACTION 0.6 of the row's width,
    // or a fling past SWIPE_ESCAPE_VELOCITY (500dp/s).
    readonly property real dismissFraction: 0.6
    readonly property real escapeVelocity: 500
    // Touch slop before a drag is a drag rather than a sloppy tap.
    readonly property real slop: 8
    // DEFAULT_ESCAPE_ANIMATION_DURATION / MAX_ESCAPE_ANIMATION_DURATION.
    readonly property int escapeDurationDefault: 200
    readonly property int escapeDurationMax: 400

    property real _pressX: 0
    property real _pressY: 0
    property real _lastX: 0
    property real _lastTime: 0
    property real _velocity: 0
    property bool _gestureActive: false

    function swipeOffsetFor(index: int): real {
        if (root.swipeIndex < 0 || root.swipeIsChild)
            return 0;
        const diff = Math.abs(root.swipeIndex - index);
        if (diff === 0)
            return root.swipeDistance;
        if (Math.abs(root.swipeDistance) > root.width * root.dismissFraction)
            return 0;
        if (diff === 1)
            return root.swipeDistance * 0.3;
        if (diff === 2)
            return root.swipeDistance * 0.1;
        return 0;
    }

    Column {
        id: column
        width: parent.width
        spacing: root.cardGap

        move: Transition { // Neighbours close the gap a dismissal leaves
            NumberAnimation {
                properties: "y"
                duration: Appearance.animation.elementMove.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
        }

        Repeater {
            id: cardRepeater
            // Names rather than group objects: a string compares by value, so
            // ScriptModel can diff the list and leave untouched delegates
            // alone instead of rebuilding every card on every notification.
            model: ScriptModel {
                values: root.cardNames
            }

            delegate: NotificationStackCard {
                id: card
                required property int index
                required property string modelData

                readonly property string appName: card.modelData

                width: column.width
                height: implicitHeight
                group: root.groupFor(card.appName)
                expanded: root.isExpanded(card.appName)
                showActions: root.showActions
                contentHidden: root.contentHidden
                fontScale: root.fontScale
                surfaceOpacity: root.surfaceOpacity
                swipeOffset: root.swipeOffsetFor(card.index)
                swiping: (root._gestureActive && root.swipeCommitted) || escapeAnim.running
                childSwipeId: root.swipeIsChild ? root.swipeChildId : -1
                childSwipeOffset: root.swipeIsChild ? root.swipeDistance : 0
                hoverTarget: root.hoverIndex === card.index ? root.hoverTarget : ""
                pressTarget: root.pressIndex === card.index ? root.pressTarget : ""
                exiting: root.exitingNames.indexOf(card.appName) !== -1
                // AOSP staggers a batch by ANIMATION_DELAY_PER_ELEMENT_MANUAL
                // (32), capped at MAX_STAGGER_COUNT (5).
                entryDelay: Math.min(card.index ?? 0, 5) * 32
            }
        }

        Loader { // Overflow icons
            id: shelfLoader
            width: column.width
            active: root.shelfGroups.length > 0
            visible: active

            sourceComponent: NotificationStackShelf {
                groups: root.shelfGroups
                hoverTarget: root.hoverTarget === "shelf" ? "shelf" : ""
                pressTarget: root.pressTarget === "shelf" ? "shelf" : ""
            }
        }

        Loader { // Nothing to show
            id: emptyLoader
            width: column.width
            active: root.displayNames.length === 0 && !root.hideWhenEmpty
            visible: active

            sourceComponent: Rectangle {
                implicitHeight: 72
                width: column.width
                radius: Appearance.rounding.large
                color: ColorUtils.transparentize(Appearance.colors.colBackgroundSurfaceContainer, 1 - root.surfaceOpacity)

                Row {
                    anchors.centerIn: parent
                    spacing: 12

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "notifications_off"
                        iconSize: 24
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                        text: Translation.tr("No notifications")
                    }
                }
            }
        }
    }

    // ── Fly-off ──────────────────────────────────────────────────────────────
    NumberAnimation {
        id: escapeAnim
        target: root
        property: "swipeDistance"
        easing.type: Easing.BezierSpline
        // Leaving is accelerating: the user has already decided.
        easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        onFinished: root._commitDismiss()
    }

    property var _dismissIds: []

    function _commitDismiss(): void {
        const ids = root._dismissIds;
        root._dismissIds = [];
        root._resetGesture();
        for (let i = 0; i < ids.length; i++)
            Notifications.discardNotification(ids[i]);
    }

    function _resetGesture(): void {
        root.swipeIndex = -1;
        root.swipeDistance = 0;
        root.swipeCommitted = false;
        root.swipeIsChild = false;
        root.swipeChildId = -1;
        root.pressTarget = "";
        root.pressIndex = -1;
        root._gestureActive = false;
    }

    function _cardAt(index: int): Item {
        return index >= 0 && index < cardRepeater.count ? cardRepeater.itemAt(index) : null;
    }

    function _idsFor(name: string): var {
        const g = root.groupFor(name);
        const notifs = g?.notifications ?? [];
        const ids = [];
        for (let i = 0; i < notifs.length; i++)
            ids.push(notifs[i].notificationId);
        return ids;
    }

    // ── Pointer API, in this item's own coordinates ───────────────────────────
    /** Which card, if any, sits under the point. -1 for none. */
    function indexAt(px: real, py: real): int {
        for (let i = 0; i < cardRepeater.count; i++) {
            const item = cardRepeater.itemAt(i);
            if (!item || !item.visible)
                continue;
            const p = root.mapToItem(item, px, py);
            if (p.x >= 0 && p.y >= 0 && p.x <= item.width && p.y <= item.height)
                return i;
        }
        return -1;
    }

    function targetAt(px: real, py: real): string {
        const index = root.indexAt(px, py);
        if (index >= 0) {
            const item = root._cardAt(index);
            const p = root.mapToItem(item, px, py);
            return item.hitTest(p.x, p.y);
        }
        if (shelfLoader.item) {
            const p = root.mapToItem(shelfLoader.item, px, py);
            if (shelfLoader.item.hitTest(p.x, p.y).length > 0)
                return "shelf";
        }
        return "";
    }

    function setHover(px: real, py: real): void {
        if (!root.interactive) {
            root.clearHover();
            return;
        }
        root.hoverIndex = root.indexAt(px, py);
        root.hoverTarget = root.targetAt(px, py);
    }

    function clearHover(): void {
        root.hoverIndex = -1;
        root.hoverTarget = "";
    }

    /** True when the point is on something this stack wants the gesture for. */
    function beginGesture(px: real, py: real): bool {
        if (!root.interactive || escapeAnim.running)
            return false;
        const target = root.targetAt(px, py);
        if (target.length === 0)
            return false;

        root.pressIndex = root.indexAt(px, py);
        root.pressTarget = target;
        root._pressX = px;
        root._pressY = py;
        root._lastX = px;
        root._lastTime = Date.now();
        root._velocity = 0;
        root._gestureActive = true;
        root.swipeCommitted = false;
        root.swipeIndex = -1;
        root.swipeDistance = 0;
        root.swipeIsChild = false;
        root.swipeChildId = -1;
        return true;
    }

    /**
     * Returns false once the gesture is clearly not ours - a mostly vertical
     * drag, which the widget hands on to its own move gesture. There is nothing
     * to scroll here, so vertical travel is unambiguous.
     */
    function updateGesture(px: real, py: real): bool {
        if (!root._gestureActive)
            return false;

        const dx = px - root._pressX;
        const dy = py - root._pressY;

        if (!root.swipeCommitted) {
            if (Math.abs(dy) > root.slop && Math.abs(dy) >= Math.abs(dx))
                return false;
            if (Math.abs(dx) <= root.slop)
                return true;
            if (!root.dismissOnSwipe || root.pressTarget === "shelf")
                return false;
            const card = root._cardAt(root.pressIndex);
            if (!card)
                return false;
            if (!card.swipesWholeCard(root.pressTarget)) {
                // An open group only lets its children go one at a time; a
                // horizontal drag on its header is not ours.
                if (!root.pressTarget.startsWith("child:"))
                    return false;
                root.swipeIsChild = true;
                root.swipeChildId = parseInt(root.pressTarget.substring(6));
            }
            root.swipeCommitted = true;
            root.swipeIndex = root.pressIndex;
            // A committed swipe is no longer a press on a button.
            root.pressTarget = "body";
        }

        const now = Date.now();
        const dt = Math.max(1, now - root._lastTime);
        root._velocity = (px - root._lastX) * 1000 / dt;
        root._lastX = px;
        root._lastTime = now;
        root.swipeDistance = dx;
        return true;
    }

    function endGesture(px: real, py: real, button: int): void {
        if (!root._gestureActive)
            return;

        if (root.swipeCommitted) {
            root._finishSwipe();
            return;
        }

        const target = root.pressTarget;
        const index = root.pressIndex;
        const moved = Math.abs(px - root._pressX) > root.slop || Math.abs(py - root._pressY) > root.slop;
        root._resetGesture();
        if (moved)
            return;

        if (button === Qt.MiddleButton) {
            root._dismissTarget(index, target);
            return;
        }
        root._activate(index, target, button);
    }

    function cancelGesture(): void {
        if (root.swipeCommitted)
            root._snapBack();
        else
            root._resetGesture();
    }

    function _snapBack(): void {
        // Fast spatial, which is the closest this shell has to the physics
        // spring SwipeHelper snaps back with.
        escapeAnim.stop();
        escapeAnim.from = root.swipeDistance;
        escapeAnim.to = 0;
        escapeAnim.duration = Appearance.animation.elementMoveSmall.duration;
        escapeAnim.easing.bezierCurve = Appearance.animationCurves.expressiveFastSpatial;
        root._dismissIds = [];
        escapeAnim.start();
    }

    function _finishSwipe(): void {
        const distance = root.swipeDistance;
        const farEnough = Math.abs(distance) > root.width * root.dismissFraction;
        const fastEnough = Math.abs(root._velocity) > root.escapeVelocity
            && (root._velocity > 0) === (distance > 0);

        if (!farEnough && !fastEnough) {
            root._snapBack();
            return;
        }

        const name = root.cardNames[root.swipeIndex];
        const ids = root.swipeIsChild ? [root.swipeChildId] : root._idsFor(name);
        const goingLeft = fastEnough ? root._velocity < 0 : distance < 0;
        // dismissOvershoot, so the row is fully clear of the gap it leaves.
        const to = (root.width + 20) * (goingLeft ? -1 : 1);

        escapeAnim.stop();
        escapeAnim.from = distance;
        escapeAnim.to = to;
        escapeAnim.duration = root._velocity !== 0
            ? Math.min(root.escapeDurationMax, Math.abs(to - distance) * 1000 / Math.abs(root._velocity))
            : root.escapeDurationDefault;
        escapeAnim.easing.bezierCurve = Appearance.animationCurves.emphasizedAccel;
        root._dismissIds = ids;
        root._gestureActive = false;
        escapeAnim.start();
    }

    function _dismissTarget(index: int, target: string): void {
        if (target.startsWith("child:")) {
            Notifications.discardNotification(parseInt(target.substring(6)));
            return;
        }
        const name = root.cardNames[index];
        if (name === undefined)
            return;
        const ids = root._idsFor(name);
        for (let i = 0; i < ids.length; i++)
            Notifications.discardNotification(ids[i]);
    }

    function _activate(index: int, target: string, button: int): void {
        if (target === "shelf") {
            root.shelfExpanded = !root.shelfExpanded;
            return;
        }
        const name = root.cardNames[index];
        if (name === undefined)
            return;

        if (target === "close") {
            root._dismissTarget(index, target);
            return;
        }
        if (target === "pill" || button === Qt.RightButton) {
            root.toggleExpanded(name);
            return;
        }
        if (target.startsWith("action:")) {
            const parts = target.split(":");
            const notifId = parseInt(parts[1]);
            const identifier = parts.slice(2).join(":");
            root.notificationInvoked(notifId, identifier);
            Notifications.attemptInvokeAction(notifId, identifier);
            return;
        }
        if (target.startsWith("child:") || target === "body") {
            if (root.bodyAction === "invoke") {
                const g = root.groupFor(name);
                const newest = (g?.notifications ?? []).slice(-1)[0];
                const actions = newest?.actions ?? [];
                if (actions.length > 0) {
                    root.notificationInvoked(newest.notificationId, actions[0].identifier);
                    Notifications.attemptInvokeAction(newest.notificationId, actions[0].identifier);
                    return;
                }
            }
            root.toggleExpanded(name);
        }
    }

    Connections {
        target: GlobalStates
        // Re-locking resets the lock screen's stack, the way Android does.
        function onScreenLockedChanged() {
            root.collapseAll();
            root.clearHover();
            root.cancelGesture();
        }
    }
}
