pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// Stub. The ported desktop widgets read KDE Connect for phone battery and file
// sharing; this shell has no KDE Connect bridge, so they see "nothing paired".
// ponytail: replace with a real bridge (see ii-p3drovfx services/KdeConnectService.qml)
// if the phone widgets are wanted. Members here are exactly what those widgets read.
Singleton {
    readonly property bool available: false
    readonly property var activeDevice: null
    readonly property string activeDeviceId: ""
    readonly property bool activeReachable: false
    readonly property list<var> devices: []

    function shareFile(deviceId: string, path: string): void {}
}
