pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs
import qs.services
import qs.modules.common.utils
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

/**
 * Provides extra features not in Quickshell.Services.Notifications:
 *  - Persistent storage
 *  - Popup notifications, with timeout
 *  - Notification groups by app
 */
Singleton {
	id: root
    component Notif: QtObject {
        id: wrapper
        required property int notificationId // Could just be `id` but it conflicts with the default prop in QtObject
        property Notification notification
        property list<var> actions: notification?.actions.map((action) => ({
            "identifier": action.identifier,
            "text": action.text,
        })) ?? []
        property bool popup: false
        property bool isTransient: notification?.hints.transient ?? false
        property string appIcon: notification?.appIcon ?? ""
        property string appName: notification?.appName ?? ""
        property string body: notification?.body ?? ""
        property string image: notification?.image ?? ""
        property string summary: notification?.summary ?? ""
        property double time
        property string urgency: notification?.urgency.toString() ?? "normal"
        property Timer timer
        property bool timeoutPaused: false
        onPopupChanged: if (!popup) timeoutPaused = false

        // Fallback while the delivery observer is unavailable. Coalesce field
        // signals after Qt has updated every binding; normally the observer
        // handles replacements, including ones with no changed properties.
        function queueUpdate() {
            if (root.deliveryMonitorReady) return;
            if (!notification || !root.list.includes(wrapper)) return;
            Qt.callLater(wrapper.applyUpdate);
        }

        function applyUpdate() {
            if (root.deliveryMonitorReady) return;
            if (!notification || !root.list.includes(wrapper)) return;
            root.deliverNotification(wrapper);
        }

        // This also observes changes to an existing action's text, for which
        // Notification.actionsChanged itself is not emitted.
        onActionsChanged: queueUpdate()
        property Connections notificationChanges: Connections {
            target: wrapper.notification ?? null
            function onAppNameChanged() { wrapper.queueUpdate(); }
            function onAppIconChanged() { wrapper.queueUpdate(); }
            function onSummaryChanged() { wrapper.queueUpdate(); }
            function onBodyChanged() { wrapper.queueUpdate(); }
            function onImageChanged() { wrapper.queueUpdate(); }
            function onUrgencyChanged() { wrapper.queueUpdate(); }
            function onHintsChanged() { wrapper.queueUpdate(); }
            function onExpireTimeoutChanged() { wrapper.queueUpdate(); }
        }

        onNotificationChanged: {
            if (notification === null) {
                root.discardNotification(notificationId);
            }
        }
    }

    function notifToJSON(notif) {
        return {
            "notificationId": notif.notificationId,
            "actions": notif.actions,
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "body": notif.body,
            "image": notif.image,
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
        }
    }
    function notifToString(notif) {
        return JSON.stringify(notifToJSON(notif), null, 2);
    }

    component NotifTimer: Timer {
        required property int notificationId
        interval: 7000
        running: true
        onTriggered: () => {
            const index = root.list.findIndex((notif) => notif.notificationId === notificationId);
            const notifObject = root.list[index];
            print("[Notifications] Notification timer triggered for ID: " + notificationId + ", transient: " + notifObject?.isTransient);
            // Discarded before its timeout: nothing left to time out.
            if (notifObject?.isTransient) root.discardNotification(notificationId);
            else if (notifObject) root.timeoutNotification(notificationId);
            destroy()
        }
    }

    property bool silent: false
    property int unread: 0
    property var filePath: Directories.notificationsPath
    property list<Notif> list: []
    property var popupList: list.filter((notif) => notif.popup);
    property bool popupInhibited: (GlobalStates?.sidebarRightOpen ?? false) || silent
    property var latestTimeForApp: ({})
    Component {
        id: notifComponent
        Notif {}
    }
    Component {
        id: notifTimerComponent
        NotifTimer {}
    }

    function stringifyList(list) {
        return JSON.stringify(list.map((notif) => notifToJSON(notif)), null, 2);
    }
    
    onListChanged: {
        const latest = Object.assign({}, root.latestTimeForApp);
        // Update latest time for each app
        root.list.forEach((notif) => {
            if (!latest[notif.appName] || notif.time > latest[notif.appName]) {
                latest[notif.appName] = Math.max(latest[notif.appName] || 0, notif.time);
            }
        });
        // Remove apps that no longer have notifications
        Object.keys(latest).forEach((appName) => {
            if (!root.list.some((notif) => notif.appName === appName)) {
                delete latest[appName];
            }
        });
        // Publish a new object so groups observe updated timestamps regardless
        // of whether their list binding ran before this change handler.
        root.latestTimeForApp = latest;
    }

    function appNameListForGroups(groups) {
        return Object.keys(groups).sort((a, b) => {
            // Sort by time, descending
            return groups[b].time - groups[a].time;
        });
    }

    function groupsForList(list) {
        const groups = {};
        list.forEach((notif) => {
            if (!groups[notif.appName]) {
                groups[notif.appName] = {
                    appName: notif.appName,
                    appIcon: notif.appIcon,
                    notifications: [],
                    time: 0
                };
            }
            groups[notif.appName].notifications.push(notif);
            // Always set to the latest time in the group
            groups[notif.appName].time = latestTimeForApp[notif.appName] || notif.time;
        });
        return groups;
    }

    property var groupsByAppName: groupsForList(root.list)
    property var popupGroupsByAppName: groupsForList(root.popupList)
    property list<string> appNameList: appNameListForGroups(root.groupsByAppName)
    property list<string> popupAppNameList: appNameListForGroups(root.popupGroupsByAppName)

    // Quickshell's notification IDs starts at 1 on each run, while saved notifications
    // can already contain higher IDs. This is for avoiding id collisions
    property int idOffset
    property bool historyReady: false
    property list<Notification> pendingNotifications: []
    signal initDone();
    signal notify(notification: var);
    signal discard(id: int);
    signal discardAll();
    signal timeout(id: var);

    // Quickshell 0.3.2 emits no update event for identical replacements. Watch
    // successful Notify replies so every delivery has an event, after its fields
    // have been updated. Start the server once the observer is subscribed.
    property bool deliveryMonitorReady: false
    property bool serverStarted: false
    readonly property var notifServer: serverLoader.item
    readonly property var trackedNotifications: root.notifServer?.trackedNotifications.values ?? []

    KeepAliveProcess {
        args: ["python3", Quickshell.shellPath("scripts/notifications/watch.py")]
        onRunningChanged: if (!running) root.deliveryMonitorReady = false
        // Keep ordinary delivery working if the observer cannot start. The
        // field-change handlers above remain the fallback during an outage.
        onExited: root.serverStarted = true
        stdout: SplitParser {
            onRead: line => {
                const event = JSON.parse(line);
                if (event.ready) {
                    root.deliveryMonitorReady = true;
                    root.serverStarted = true;
                } else if (event.replaced) {
                    const notif = root.list.find(n => n.notification?.id === event.replaced);
                    if (notif) root.deliverNotification(notif);
                }
            }
        }
    }

    LazyLoader {
        id: serverLoader
        active: root.serverStarted
        component: NotificationServer {
            id: server
            // actionIconsSupported: true
            actionsSupported: true
            bodyHyperlinksSupported: true
            bodyImagesSupported: true
            bodyMarkupSupported: true
            bodySupported: true
            imageSupported: true
            keepOnReload: false
            persistenceSupported: true

            // Phone notifications relayed by KDE Connect belong to the Continuity
            // page only - mirroring them into the desktop list is the same buzz
            // twice. Untracked notifications are dropped by the server for us.
            function fromPhone(notification) {
                return /kdeconnect/i.test(notification.desktopEntry ?? "")
                    || /kdeconnect/i.test(notification.appName ?? "");
            }

            onNotification: (notification) => {
                if (server.fromPhone(notification) && !(Config.options?.notifications.phoneOnDesktop ?? false)) return;
                notification.tracked = true
                root.addNotification(notification);
            }
        }
    }

    function addNotification(notification) {
        // Keep the real server object alive while the asynchronous history read
        // reserves its IDs. Do not create a wrapper or write the file before it.
        if (!root.historyReady) {
            root.pendingNotifications = [...root.pendingNotifications, notification];
            return;
        }
        // The sender may have closed a queued notification while history loaded.
        if (!notification || !notification.tracked) return;
        const notif = notifComponent.createObject(root, {
            "notificationId": notification.id + root.idOffset,
            "notification": notification,
            "time": Date.now(),
        });
        root.deliverNotification(notif);
    }

    function deliverNotification(notif) {
        const notification = notif.notification;
        // A replacement is the same notification updated in place: a download's
        // progress, the next track, a phone's ongoing call. Like Android's
        // setOnlyAlertOnce it alerts when it first arrives, not on every update.
        const replacement = root.list.includes(notif);
        const previousTime = notif.time;
        const now = Date.now();
        const lastTime = root.latestTimeForApp[notification.appName] || 0;
        const cooledDown = Config.options.notifications.cooldown && now - lastTime < 5000;

        // An open sidebar holds the popup back, not the sound; Do Not Disturb
        // holds both. Low urgency is quiet, and an app may name its own sound.
        const hints = notification.hints;
        if (!replacement && !root.silent && !cooledDown && notification.urgency !== NotificationUrgency.Low && !hints["suppress-sound"])
            SoundService.playEvent("notifications", [hints["sound-file"], hints["sound-name"], ...SoundService.events.notifications].filter(Boolean));

        // Replace the old deadline even if it was stopped by hovering, or the
        // replacement asks to remain visible indefinitely (expireTimeout = 0).
        if (notif.timer) {
            notif.timer.stop();
            notif.timer.destroy();
            notif.timer = null;
        }
        notif.time = now;
        // Cooldown suppresses a new popup without hiding one already visible.
        notif.popup = !root.popupInhibited && (!cooledDown || notif.popup);
        if (notif.popup && notification.expireTimeout != 0) {
            // Owned by the wrapper so stopped timers die with their notification.
            notif.timer = notifTimerComponent.createObject(notif, {
                "notificationId": notif.notificationId,
                "interval": notification.expireTimeout < 0 ? (Config?.options.notifications.timeout ?? 7000) : notification.expireTimeout,
                "running": !notif.timeoutPaused,
            });
        }

        // Keep the wrapper stable for the views, but refresh grouping and sorting
        // after a replacement changes the app name or delivery time.
        if (replacement) root.triggerListChange();
        else root.list = [...root.list, notif];
        // DND holds the popup back, not the unread count. An update was counted already.
        if (!replacement && !(GlobalStates?.sidebarRightOpen ?? false)) root.unread++;
        root.notify(notif);
        if (Config.options.notifications.history.enable) root.recordHistory(notif, replacement ? previousTime : -1);
        notifFileView.setText(stringifyList(root.list));
    }

    // ponytail: whole file rewritten per notification, capped so that stays cheap;
    // move to JSONL appends if the cap ever needs to grow by orders of magnitude.
    readonly property int historyLimit: 1000
    // An update rewrites its own entry, found by id and the time it was saved
    // with: ids from older sessions recur, and a file of copies of one download's
    // progress is no history.
    function recordHistory(notif, previousTime) {
        let history = [];
        try { history = JSON.parse(historyFileView.text() || "[]"); } catch (e) {}
        const entry = notifToJSON(notif);
        delete entry.actions; // dead once the sender is gone, same as the reload path
        let index = -1;
        for (let i = history.length - 1; i >= 0 && previousTime >= 0; i--) {
            if (history[i].notificationId === entry.notificationId && history[i].time === previousTime) {
                index = i;
                break;
            }
        }
        if (index >= 0) history[index] = entry;
        else history.push(entry);
        historyFileView.setText(JSON.stringify(history.slice(-root.historyLimit)));
    }

    // Settings clears the history by writing this file, so re-read it rather
    // than keeping a copy that would write the cleared entries back.
    FileView {
        id: historyFileView
        path: Directories.notificationHistoryPath
        blockLoading: true
        printErrors: false // absent until the first entry
        watchChanges: true
        onFileChanged: reload()
    }

    function markAllRead() {
        root.unread = 0;
    }

    function discardNotification(id) {
        console.log("[Notifications] Discarding notification with ID: " + id);
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        const notifServerIndex = root.trackedNotifications.findIndex((notif) => notif.id + root.idOffset === id);
        if (index !== -1) {
            root._release(root.list.splice(index, 1));
            notifFileView.setText(stringifyList(root.list));
            triggerListChange()
        }
        if (notifServerIndex !== -1) {
            root.trackedNotifications[notifServerIndex].dismiss()
        }
        root.discard(id); // Emit signal
    }

    function discardAllNotifications() {
        root._release(root.list);
        root.list = []
        triggerListChange()
        notifFileView.setText(stringifyList(root.list));
        root.trackedNotifications.forEach((notif) => {
            notif.dismiss()
        })
        root.discardAll();
    }

    function cancelTimeout(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        const notif = root.list[index];
        if (!notif) return;
        notif.timeoutPaused = true;
        notif.timer?.stop();
    }

    function resumeTimeout(id) {
        const notif = root.list.find(n => n.notificationId === id);
        if (!notif) return;
        notif.timeoutPaused = false;
        if (notif.popup) notif.timer?.restart();
    }

    function timeoutNotification(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null) {
            root.list[index].timeoutPaused = false;
            root.list[index].popup = false;
        }
        root.timeout(id);
    }

    function timeoutAll() {
        root.popupList.forEach((notif) => {
            root.timeout(notif.notificationId);
        })
        root.popupList.forEach((notif) => {
            notif.popup = false;
        });
    }

    function attemptInvokeAction(id, notifIdentifier) {
        console.log("[Notifications] Attempting to invoke action with identifier: " + notifIdentifier + " for notification ID: " + id);
        const notification = root.trackedNotifications.find((notif) => notif.id + root.idOffset === id);
        const action = notification?.actions.find((action) => action.identifier === notifIdentifier);
        if (!action) return;
        // invoke() already dismisses non-resident notifications. Their wrapper
        // is removed by onNotificationChanged; resident notifications stay live.
        action.invoke();
    }

    // A discarded Notif is created with `root` as its parent, so taking it off
    // the list alone never frees it. It is not destroyed on the spot either: the
    // row it was drawn in is still sliding out, bound to it, and destroying it
    // under that row blanks the text and logs a null read per binding. It waits
    // out the slowest motion spec instead, which every exit is shorter than.
    // Two generations, so one discarded just before a tick still gets a full
    // interval: each tick destroys what was already waiting and moves the rest up.
    property var _discarded: []
    property var _expiring: []
    function _release(notifs) {
        root._discarded.push(...notifs);
        reaper.start();
    }
    Timer {
        id: reaper
        interval: Appearance.animationCurves.expressiveSlowSpatialDuration
        repeat: true
        onTriggered: {
            root._expiring.forEach((notif) => notif.destroy());
            root._expiring = root._discarded;
            root._discarded = [];
            if (root._expiring.length === 0) stop();
        }
    }

    function triggerListChange() {
        // Assigning an equal list of the same wrappers emits no change in Qt.
        // Replacements still need the list's derived models to refresh.
        root.listChanged();
    }

    function refresh() {
        notifFileView.reload()
    }

    function restoreNotifications(saved) {
        // History is a startup snapshot. A later reload must not replace live
        // wrappers, drop their actions or change the server-to-wrapper ID offset.
        if (root.historyReady) return;
        root.list = saved.map((notif) => notifComponent.createObject(root, {
            "notificationId": notif.notificationId,
            "actions": [], // Saved senders are no longer tracked by this server.
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "body": notif.body,
            "image": notif.image,
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
        }));
        root.idOffset = root.list.reduce((maxId, notif) => Math.max(maxId, notif.notificationId), 0);
        root.historyReady = true;

        const pending = root.pendingNotifications.slice();
        root.pendingNotifications = [];
        pending.forEach((notification) => root.addNotification(notification));
        root.initDone();
    }

    Component.onCompleted: {
        refresh()
    }

    FileView {
        id: notifFileView
        path: Qt.resolvedUrl(filePath)
        onLoaded: {
            if (root.historyReady) return;
            const fileContents = notifFileView.text()
            let saved = [];
            try {
                saved = JSON.parse(fileContents);
                if (!Array.isArray(saved)) throw new Error("Expected a notification list");
            } catch (e) {
                console.warn("[Notifications] History file is not valid JSON, starting empty:", e);
                saved = [];
            }
            console.log("[Notifications] File loaded")
            root.restoreNotifications(saved);
        }
        onLoadFailed: (error) => {
            if (root.historyReady) return;
            // Missing or unreadable history must still release queued arrivals.
            root.restoreNotifications([]);
            if(error == FileViewError.FileNotFound) {
                console.log("[Notifications] File not found, creating new file.")
                notifFileView.setText(stringifyList(root.list));
            } else {
                console.log("[Notifications] Error loading file: " + error)
            }
        }
    }
}
