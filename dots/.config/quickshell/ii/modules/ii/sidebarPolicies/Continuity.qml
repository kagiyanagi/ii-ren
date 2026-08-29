pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.sidebarPolicies.continuity
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

/**
 * Continuity - everything that is "yours but not this machine" in one
 * scrolling page: the phone over KDE Connect, whatever bluetooth device is
 * on your head, and the tailnet.
 */
Item {
    id: root
    property real padding: 10
    // The phone card is a door: tapping it swaps the rest of the page for the
    // notification list, which is the only place phone notifications show up.
    property bool notificationsOpen: false
    // The layout follows the toggle only at the midpoint of the crossfade, so
    // the two pages never occupy the column at the same time and nothing jumps.
    property bool showingNotifications: false
    property real pageOpacity: 1
    property real pageShift: 0
    onNotificationsOpenChanged: pageSwap.restart()

    SequentialAnimation {
        id: pageSwap
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "pageOpacity"; to: 0
                duration: Appearance.animationCurves.expressiveFastEffectsDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
            }
            NumberAnimation {
                target: root; property: "pageShift"
                to: root.notificationsOpen ? -12 : 12
                duration: Appearance.animationCurves.expressiveFastEffectsDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
            }
        }
        ScriptAction {
            script: {
                root.showingNotifications = root.notificationsOpen;
                root.pageShift = root.notificationsOpen ? 12 : -12; // enter from the other side
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "pageOpacity"; to: 1
                duration: Appearance.animationCurves.expressiveEffectsDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
            NumberAnimation {
                target: root; property: "pageShift"; to: 0
                duration: Appearance.animationCurves.expressiveDefaultSpatialDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
        }
    }

    // Both services idle until something is actually looking at them.
    readonly property bool pageActive: root.visible && (root.QsWindow.window?.visible ?? false)
    onPageActiveChanged: {
        Tailscale.watchers = Math.max(0, Tailscale.watchers + (root.pageActive ? 1 : -1));
        if (root.pageActive) Tailscale.refresh();
    }
    Component.onDestruction: if (root.pageActive) Tailscale.watchers = Math.max(0, Tailscale.watchers - 1)

    readonly property var phone: KdeConnectService.activeDevice
    readonly property list<var> audioDevices: Bluetooth.devices.values
        .filter(d => d.connected && d.batteryAvailable)

    readonly property bool canShowNotifications: KdeConnectService.activeReachable
        && KdeConnectService.hasPlugin("kdeconnect_notifications")
    onCanShowNotificationsChanged: if (!root.canShowNotifications) root.notificationsOpen = false

    readonly property string phoneStatus: {
        if (!KdeConnectService.installed) return Translation.tr("KDE Connect is not installed");
        if (!root.phone) return Translation.tr("Nothing paired yet");
        if (!root.phone.reachable) return Translation.tr("Out of reach");
        const bits = [Translation.tr("Connected")];
        if (root.phone.signalType !== "") bits.push(root.phone.signalType);
        return bits.join(" · ");
    }

    // One half of the swap: fades and slides with pageSwap.
    component PageSection: ColumnLayout {
        opacity: root.pageOpacity
        transform: Translate { y: root.pageShift }
    }

    component ActionPill: RippleButtonWithIcon {
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        // A lift off the card it sits on rather than a different tonal role -
        // secondaryContainer on primaryContainer was green on green.
        colBackground: ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colOnPrimaryContainer, 0.86)
        colBackgroundHover: ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colOnPrimaryContainer, 0.76)
        materialIconFill: false

        // A small spring pop on press/hover - the same tactile feedback
        // Android gives its own quick-settings chips.
        scale: down ? 0.94 : (hovered ? 1.04 : 1.0)
        Behavior on scale {
            NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
        }
    }

    // A short line for "nothing here yet / here's why" - every section has one.
    component EmptyHint: StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 8
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        wrapMode: Text.Wrap
    }

    // One phone notification. These are the only place Android notifications
    // surface - services/Notifications.qml drops the KDE Connect copies so the
    // desktop stays quiet.
    component PhoneNotification: Rectangle {
        id: notif
        required property var modelData
        width: notif.ListView.view?.width ?? 0
        implicitHeight: notifRow.implicitHeight + 28
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2

        RowLayout {
            id: notifRow
            anchors {
                left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                leftMargin: 14; rightMargin: 8
            }
            spacing: 12

            NotificationAppIcon {
                Layout.alignment: Qt.AlignTop
                implicitSize: 40
                summary: notif.modelData.appName
                // KDE Connect drops the phone app's icon in /tmp; the shape
                // falls back to a guessed material symbol when it hasn't yet.
                image: notif.modelData.iconPath ? `file://${notif.modelData.iconPath}` : ""
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: notif.modelData.appName
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: notif.modelData.title !== ""
                    text: notif.modelData.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    visible: notif.modelData.text !== ""
                    text: notif.modelData.text
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                }
            }

            RippleButton {
                Layout.alignment: Qt.AlignTop
                visible: notif.modelData.dismissable
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                onClicked: KdeConnectService.dismissNotification(notif.modelData.id)
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    text: "close"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    component SectionHeader: RowLayout {
        id: header
        property string icon: ""
        property string title: ""
        property string trailing: ""
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 8
        MaterialSymbol {
            text: header.icon
            iconSize: Appearance.font.pixelSize.normal
            fill: 1
            color: Appearance.colors.colSubtext
        }
        StyledText {
            text: header.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: Appearance.colors.colSubtext
        }
        Item { Layout.fillWidth: true }
        StyledText {
            visible: header.trailing !== ""
            text: header.trailing
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    // Bottom bar over the notification list: mute toggle, count, clear all.
    component BarPill: RippleButton {
        implicitHeight: 44
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundToggled: Appearance.colors.colPrimaryContainer
        colBackgroundToggledHover: Appearance.colors.colPrimaryContainerHover
    }

    RowLayout {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: root.padding
        }
        visible: root.showingNotifications
        opacity: root.pageOpacity
        spacing: 6
        z: 1

        BarPill { // Mirror onto the desktop as well, off by default
            implicitWidth: 56
            toggled: Config.options.notifications.phoneOnDesktop
            onClicked: Config.options.notifications.phoneOnDesktop = !Config.options.notifications.phoneOnDesktop
            StyledToolTip { text: Translation.tr("Also show phone notifications on the desktop") }
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                text: Config.options.notifications.phoneOnDesktop ? "notifications_active" : "notifications_off"
                iconSize: Appearance.font.pixelSize.huge
                fill: Config.options.notifications.phoneOnDesktop ? 1 : 0
                color: Config.options.notifications.phoneOnDesktop
                    ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
            }
        }

        Rectangle { // Count, not a button - nothing to press it for
            Layout.fillWidth: true
            implicitHeight: 44
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2
            StyledText {
                anchors.centerIn: parent
                text: KdeConnectService.notifications.length === 1
                    ? Translation.tr("1 notification")
                    : Translation.tr("%1 notifications").arg(KdeConnectService.notifications.length)
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }
        }

        BarPill {
            implicitWidth: 56
            enabled: KdeConnectService.notifications.length > 0
            onClicked: KdeConnectService.dismissAllNotifications()
            StyledToolTip { text: Translation.tr("Clear all") }
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                text: "delete_sweep"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnLayer2
            }
        }
    }

    StyledFlickable {
        id: flickable
        anchors.fill: parent
        anchors.margins: root.padding
        contentHeight: contentColumn.height
        clip: true

        ColumnLayout {
            id: contentColumn
            width: flickable.width
            // Stretch to fill the panel even on a quiet day - otherwise a
            // couple of short cards leave a dead void under a full-height
            // sidebar.
            height: Math.max(implicitHeight, flickable.height)
            spacing: 8

            DeviceCard { // Phone
                icon: root.phone?.type === "tablet" ? "tablet" : "smartphone"
                name: root.phone?.name ?? Translation.tr("No phone")
                status: root.phoneStatus
                prominent: true
                dimmed: !(root.phone?.reachable ?? false)
                charge: (root.phone?.hasBattery ?? false) ? root.phone.charge : -1
                charging: root.phone?.charging ?? false
                acceptsDrops: KdeConnectService.activeReachable && KdeConnectService.hasPlugin("kdeconnect_share")
                onFilesDropped: urls => urls.forEach(url => KdeConnectService.shareUrl(String(url)))
                clickable: root.canShowNotifications
                expanded: root.notificationsOpen
                onClicked: root.notificationsOpen = !root.notificationsOpen

                Flow { // Phone actions
                    Layout.fillWidth: true
                    visible: KdeConnectService.activeReachable
                    spacing: 6

                    ActionPill {
                        visible: KdeConnectService.hasPlugin("kdeconnect_findmyphone")
                        materialIcon: "notifications_active"
                        mainText: Translation.tr("Ring")
                        onClicked: KdeConnectService.ring()
                    }
                    ActionPill {
                        visible: KdeConnectService.hasPlugin("kdeconnect_share")
                        materialIcon: "upload_file"
                        mainText: Translation.tr("Send file")
                        onClicked: KdeConnectService.pickAndShareFile()
                    }
                    ActionPill {
                        visible: KdeConnectService.hasPlugin("kdeconnect_sms")
                        materialIcon: "chat"
                        mainText: Translation.tr("Messages")
                        onClicked: KdeConnectService.openSms()
                    }
                    ActionPill {
                        visible: KdeConnectService.hasPlugin("kdeconnect_clipboard")
                        materialIcon: "content_paste_go"
                        mainText: Translation.tr("Push clipboard")
                        onClicked: KdeConnectService.sendClipboard()
                    }
                    ActionPill {
                        visible: KdeConnectService.hasPlugin("kdeconnect_sftp")
                        materialIcon: "folder_open"
                        mainText: Translation.tr("Browse")
                        onClicked: KdeConnectService.mountSftp()
                    }
                }

                ActionPill { // Pairing escape hatch
                    Layout.alignment: Qt.AlignHCenter
                    visible: KdeConnectService.installed && !KdeConnectService.activeReachable
                    materialIcon: "phonelink_ring"
                    mainText: root.phone ? Translation.tr("Open KDE Connect") : Translation.tr("Pair a device")
                    onClicked: KdeConnectService.openPairingApp()
                }
            }

            PageSection { // Phone notifications
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: 4
                visible: root.showingNotifications
                spacing: 8

                SectionHeader {
                    icon: "notifications"
                    title: Translation.tr("Notifications")
                    trailing: KdeConnectService.notifications.length > 0 ? String(KdeConnectService.notifications.length) : ""
                }

                EmptyHint {
                    visible: KdeConnectService.notifications.length === 0
                    text: Translation.tr("Nothing on your phone right now")
                }

                // Its own scroll box: the list is unbounded, the page is not.
                // A ListView rather than a Repeater purely for the transitions -
                // dismissing slides the row out and closes the gap, like Android.
                StyledListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8
                    clip: true
                    animateMovement: true
                    bottomMargin: 56 // Room to scroll the last row out from under the bottom bar
                    // Diff by notification id, otherwise every snapshot from the
                    // monitor looks like a fresh list and the whole page flashes.
                    model: ScriptModel {
                        objectProp: "id"
                        values: KdeConnectService.notifications
                    }
                    delegate: PhoneNotification {}
                }
            }

            PageSection { // Audio
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: !root.showingNotifications && root.audioDevices.length > 0
                spacing: 8

                SectionHeader { icon: "headphones"; title: Translation.tr("Audio") }

                Repeater {
                    model: ScriptModel { values: root.audioDevices }
                    DeviceCard {
                        required property var modelData
                        icon: Icons.getBluetoothDeviceMaterialSymbol(modelData?.icon ?? "")
                        name: modelData?.deviceName ?? modelData?.name ?? ""
                        status: Translation.tr("Connected")
                        // BlueZ reports 0-1; the card speaks percent like everything else.
                        charge: Math.round((modelData?.battery ?? 0) * 100)
                    }
                }
            }

            PageSection { // Tailnet
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: !root.showingNotifications && Tailscale.installed
                spacing: 8

                SectionHeader {
                    icon: "lan"
                    title: Translation.tr("Tailnet")
                    trailing: Tailscale.running && Tailscale.exitNodeIp !== ""
                        ? Translation.tr("via exit node")
                        : (Tailscale.running ? `${Tailscale.peers.filter(p => p.online).length}/${Tailscale.peers.length}` : "")
                }

                EmptyHint {
                    visible: !Tailscale.running
                    text: Translation.tr("Tailscale is %1").arg(Tailscale.backendState.toLowerCase() || Translation.tr("stopped"))
                }

                Repeater {
                    model: ScriptModel { values: Tailscale.running ? Tailscale.peers : [] }
                    TailnetPeerItem {}
                }

                EmptyHint {
                    visible: Tailscale.running && Tailscale.peers.length === 0
                    text: Translation.tr("No tailnet peers yet")
                }
            }

            Item { // Fills whatever's left below the real cards.
                visible: !root.showingNotifications
                opacity: root.pageOpacity
                transform: Translate { y: root.pageShift }
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 120

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialShape {
                        Layout.alignment: Qt.AlignHCenter
                        shape: MaterialShape.Shape.Puffy
                        implicitSize: 56
                        color: Appearance.colors.colLayer2
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "task_alt"
                            iconSize: 26
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("That's everything connected right now")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
