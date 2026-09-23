pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool packageManagerRunning: false
    property bool downloadRunning: false
    // logind's answer per power action: "yes", "challenge" (polkit will ask),
    // "no" (not permitted) or "na" (this machine cannot, e.g. no hibernation
    // image). Kept across opens, so a tile does not flash enabled while the
    // query reruns; a method missing from it has not answered, and is allowed.
    property var capabilities: ({})

    function can(method) {
        return !["no", "na"].includes(root.capabilities[method]);
    }

    function refresh() {
        packageManagerRunning = false;
        downloadRunning = false;
        detectPackageManagerProc.running = false;
        detectPackageManagerProc.running = true;
        detectDownloadProc.running = false;
        detectDownloadProc.running = true;
        detectCapabilitiesProc.running = false;
        detectCapabilitiesProc.running = true;
    }

    Process {
        id: detectPackageManagerProc
        command: ["bash", "-c", "pidof yay paru dnf zypper apt apx xbps snap apk yum epsi pikman || ls /var/lib/pacman/db.lck"]
        onExited: (exitCode, exitStatus) => {
            root.packageManagerRunning = (exitCode === 0);
        }
    }

    Process {
        id: detectDownloadProc
        command: ["bash", "-c", "pidof curl wget aria2c yt-dlp || ls ~/Downloads | grep -E '\.crdownload$|\.part$'"]
        onExited: (exitCode, exitStatus) => {
            root.downloadRunning = (exitCode === 0);
        }
    }

    // One line per method, `CanHibernate s "na"`; a failed call prints the name alone.
    Process {
        id: detectCapabilitiesProc
        command: ["bash", "-c", "for m in CanSuspend CanHibernate CanPowerOff CanReboot CanRebootToFirmwareSetup; do echo \"$m $(busctl --system call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager $m 2>/dev/null)\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const answers = {};
                for (const line of text.split("\n")) {
                    const answer = line.match(/^(\w+) s "(\w+)"$/);
                    if (answer)
                        answers[answer[1]] = answer[2];
                }
                root.capabilities = answers;
            }
        }
    }
}
