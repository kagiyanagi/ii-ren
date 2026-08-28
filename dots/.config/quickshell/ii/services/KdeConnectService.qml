pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * KDE Connect bridge.
 *
 * State comes from `scripts/kdeconnect/monitor.py`, which watches the
 * org.kde.kdeconnect DBus signals and prints a full JSON snapshot whenever
 * something changes. Actions go out through `gdbus` - it ships with glib, so
 * unlike qdbus it is always present and always called the same thing.
 */
Singleton {
    id: root

    readonly property string helperPath: FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/kdeconnect/monitor.py"))

    property bool installed: false
    property bool available: false
    property list<var> devices: []
    property list<var> allNotifications: []

    // Empty means "follow the first reachable paired device", which is the
    // right answer for the overwhelmingly common one-phone case.
    property string preferredDeviceId: ""
    readonly property var activeDevice: {
        if (root.preferredDeviceId !== "") {
            const picked = root.devices.find(d => d.id === root.preferredDeviceId);
            if (picked) return picked;
        }
        return root.devices.find(d => d.paired && d.reachable)
            ?? root.devices.find(d => d.paired)
            ?? null;
    }
    readonly property string activeDeviceId: root.activeDevice?.id ?? ""
    readonly property bool activeReachable: root.activeDevice?.reachable ?? false
    readonly property list<var> notifications: root.allNotifications.filter(n => n.deviceId === root.activeDeviceId)

    function hasPlugin(name: string): bool {
        return (root.activeDevice?.plugins ?? []).includes(name);
    }

    // gdbus parses its arguments as GVariant text, so strings have to arrive
    // quoted and escaped even though there is no shell in the way.
    function _arg(value: string): string {
        return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`;
    }
    function _call(objectPath: string, method: string, args: var): void {
        if (root.activeDeviceId === "") return;
        Quickshell.execDetached(["gdbus", "call", "--session",
            "--dest", "org.kde.kdeconnect",
            "--object-path", `/modules/kdeconnect/devices/${root.activeDeviceId}${objectPath}`,
            "--method", `org.kde.kdeconnect.device.${method}`,
            ...(args ?? [])]);
    }

    function ring(): void { root._call("/findmyphone", "findmyphone.ring", []) }
    function ping(): void { root._call("/ping", "ping.sendPing", []) }
    function sendClipboard(): void { root._call("/clipboard", "clipboard.sendClipboard", []) }
    function shareText(text: string): void { root._call("/share", "share.shareText", [root._arg(text)]) }
    function shareUrl(url: string): void { root._call("/share", "share.shareUrl", [root._arg(url)]) }
    function shareFile(deviceId: string, path: string): void {
        // deviceId is part of the signature the ported desktop widgets call
        // with; routing through preferredDeviceId keeps one code path.
        if (deviceId !== "" && deviceId !== root.activeDeviceId) root.preferredDeviceId = deviceId;
        root.shareUrl(path.startsWith("file://") ? path : `file://${path}`);
    }
    function openSms(): void { root._call("/sms", "sms.launchApp", []) }
    function mountSftp(): void { root._call("/sftp", "sftp.startBrowsing", []) }
    function unpair(): void { root._call("", "unpair", []) }

    function dismissNotification(notificationId: string): void {
        if (root.activeDeviceId === "") return;
        Quickshell.execDetached(["gdbus", "call", "--session",
            "--dest", "org.kde.kdeconnect",
            "--object-path", `/modules/kdeconnect/devices/${root.activeDeviceId}/notifications/${notificationId}`,
            "--method", "org.kde.kdeconnect.device.notifications.notification.dismiss"]);
    }
    /** No dbus method dismisses the lot, so walk the ones that allow it. */
    function dismissAllNotifications(): void {
        root.notifications.filter(n => n.dismissable).forEach(n => root.dismissNotification(n.id));
    }
    function replyToNotification(replyId: string, message: string): void {
        root._call("/notifications", "notifications.sendReply", [root._arg(replyId), root._arg(message)]);
    }
    function runNotificationAction(notificationId: string, action: string): void {
        root._call("/notifications", "notifications.sendAction", [root._arg(notificationId), root._arg(action)]);
    }

    /** Opens a file picker and sends whatever is chosen. */
    function pickAndShareFile(): void {
        if (root.activeDeviceId === "") return;
        pickerProc.running = false;
        pickerProc.running = true;
    }

    function openPairingApp(): void { Quickshell.execDetached(["kdeconnect-app"]) }

    Process {
        id: availabilityProc
        running: true
        command: ["bash", "-c", "command -v kdeconnect-cli >/dev/null && command -v gdbus >/dev/null"]
        onExited: exitCode => root.installed = (exitCode === 0)
    }

    Process {
        id: monitorProc
        running: root.installed
        command: ["python3", root.helperPath]
        stdout: SplitParser {
            onRead: line => {
                if (line.trim() === "") return;
                try {
                    const snap = JSON.parse(line);
                    root.available = snap.available ?? false;
                    root.devices = snap.devices ?? [];
                    root.allNotifications = snap.notifications ?? [];
                } catch (e) {
                    console.warn("[KdeConnect] Bad snapshot:", e);
                }
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) console.warn("[KdeConnect] Monitor exited with", exitCode);
            root.available = false;
        }
    }

    Process {
        id: pickerProc
        command: ["bash", "-c",
            "if command -v kdialog >/dev/null; then kdialog --getopenfilename ~ --multiple --separate-output; "
            + "else zenity --file-selection --multiple --separator='\\n'; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                text.trim().split("\n").filter(p => p !== "").forEach(p => root.shareUrl(`file://${p}`));
            }
        }
    }
}
