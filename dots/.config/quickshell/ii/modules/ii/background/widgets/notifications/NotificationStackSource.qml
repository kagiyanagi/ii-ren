pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

/**
 * The live notification list, grouped and filtered for a lock screen.
 *
 * Kept in its own file behind a Loader so the settings app - which renders
 * widget previews in a second QApplication - never instantiates the
 * Notifications singleton and with it a second notification server.
 */
QtObject {
    id: root

    // Only what arrived since the screen locked, which is AOSP's
    // "Show seen notifications" turned off.
    property bool onlySinceLock: false
    property double sinceTime: 0
    // Freedesktop has no "silent" bucket; low urgency is the closest thing to
    // the notifications Android files under its Silent section.
    property bool showLowUrgency: true
    // A notification whose `transient` hint is set is a progress or status
    // blip, not something to leave on a lock screen.
    property bool skipTransient: true

    function accepts(notif): bool {
        if (!notif)
            return false;
        const urgency = notif.urgency ?? "";
        const critical = urgency === NotificationUrgency.Critical.toString();
        if (root.skipTransient && notif.isTransient && !critical)
            return false;
        if (!root.showLowUrgency && urgency === NotificationUrgency.Low.toString() && !critical)
            return false;
        if (root.onlySinceLock && !critical && (notif.time ?? 0) < root.sinceTime)
            return false;
        return true;
    }

    // `appNameList` is already sorted by group time, newest app first, which is
    // the order Android lists them in.
    readonly property var groups: {
        const names = Notifications.appNameList;
        const byName = Notifications.groupsByAppName;
        const out = [];
        for (let i = 0; i < names.length; i++) {
            const group = byName[names[i]];
            if (!group)
                continue;
            const kept = (group.notifications ?? []).filter(n => root.accepts(n));
            if (kept.length === 0)
                continue;
            out.push({
                "appName": group.appName,
                "appIcon": group.appIcon,
                "notifications": kept,
                "time": group.time
            });
        }
        return out;
    }
}
