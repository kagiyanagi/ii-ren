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

    readonly property string phoneStatus: {
        if (!KdeConnectService.installed) return Translation.tr("KDE Connect is not installed");
        if (!root.phone) return Translation.tr("Nothing paired yet");
        if (!root.phone.reachable) return Translation.tr("Out of reach");
        const bits = [Translation.tr("Connected")];
        if (root.phone.signalType !== "") bits.push(root.phone.signalType);
        return bits.join(" · ");
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

            ColumnLayout { // Audio
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: root.audioDevices.length > 0
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

            ColumnLayout { // Tailnet
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: Tailscale.installed
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
