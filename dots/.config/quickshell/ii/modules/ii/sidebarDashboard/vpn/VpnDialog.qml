import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// Android's VPN settings as the sidebar's other dialogs: a row per tunnel whose
// tap connects or disconnects it, and, with Tailscale up, its exit nodes as the
// DNS dialog's provider list.
WindowDialog {
    id: root
    // The sidebar dialogs' fixed height (TASTE 4.1): tunnels coming and going on
    // a poll must not re-centre the card under the pointer.
    backgroundHeight: Math.round(root.height * 0.6)

    Component.onCompleted: Vpn.refresh()

    readonly property var ts: Vpn.tailscale
    readonly property bool exitNodesShown: (root.ts?.state === "on") && root.ts.exitNodes.length > 0

    readonly property string status: {
        if (Vpn.pending["import"]) return Translation.tr("Importing…");
        const e = Vpn.errors["import"];
        if (e) return Translation.tr("Couldn't import: %1").arg(e === "failed" ? Translation.tr("not a VPN file") : e);
        if (Vpn.up.length > 0) return Translation.tr("Connected to %1").arg(Vpn.up.map(t => t.name).join(", "));
        return Translation.tr("Not connected");
    }

    function note(t): string {
        const busy = !!Vpn.pending[t.id];
        const e = Vpn.errors[t.id];
        if (busy && t.signedOut) return Translation.tr("Sign in in your browser");
        if (busy) return t.state === "off" ? Translation.tr("Connecting…") : Translation.tr("Disconnecting…");
        if (e === "password") return Translation.tr("Needs a password saved in its NetworkManager settings");
        if (e) return e === "failed" ? Translation.tr("Couldn't connect") : e;
        if (t.state === "connecting") return Translation.tr("Connecting…");
        if (t.signedOut) return Translation.tr("Signed out · tap to sign in");
        if (t.state === "on") {
            const where = t.exitNode ? Translation.tr("via %1").arg(t.exitNode) : t.ip;
            return where ? `${Translation.tr("Connected")} · ${where}` : Translation.tr("Connected");
        }
        return t.type === "tailscale" ? (t.account || Translation.tr("Off"))
            : t.type === "wireguard" ? "WireGuard" : Translation.tr("VPN");
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        WindowDialogTitle {
            text: Translation.tr("VPN")
        }
        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Vpn.errors["import"] && !Vpn.pending["import"] ? Appearance.colors.colError : Appearance.colors.colSubtext
            elide: Text.ElideRight
            text: root.status
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        PagePlaceholder {
            shown: Vpn.tunnels.length === 0
            icon: "vpn_key"
            title: Translation.tr("No VPNs set up")
            description: Translation.tr("Import a WireGuard or OpenVPN file, or install Tailscale")
            shape: MaterialShape.Shape.Cookie7Sided
        }

        StyledFlickable {
            anchors.fill: parent
            contentWidth: width
            contentHeight: body.implicitHeight
            clip: true
            visible: Vpn.tunnels.length > 0

            ColumnLayout {
                id: body
                width: parent.width
                spacing: 12

                Card {
                    Repeater {
                        model: ScriptModel {
                            // Keyed, so a poll replacing every object rebuilds no row (TASTE 4.2).
                            objectProp: "id"
                            values: Vpn.tunnels
                        }
                        delegate: TunnelRow {
                            id: tunnelRow
                            required property var modelData
                            required property int index
                            // The live object: a keyed delegate keeps the one it was built with.
                            readonly property var t: Vpn.tunnels.find(x => x.id === modelData.id) ?? modelData
                            readonly property bool on: t.state !== "off"
                            readonly property string error: Vpn.errors[t.id] ?? ""
                            first: index === 0
                            last: index === Vpn.tunnels.length - 1
                            symbol: t.type === "tailscale" ? "device_hub" : t.type === "wireguard" ? "vpn_key" : "vpn_lock"
                            name: t.name
                            note: root.note(t)
                            selected: on
                            noteError: error !== "" && !Vpn.pending[t.id]
                            onClicked: Vpn.setUp(t, !on)

                            // The row owns the state; the switch only shows it (TASTE 3.1).
                            StyledSwitch {
                                checkable: false
                                checked: tunnelRow.on
                                down: tunnelRow.down
                                focusPolicy: Qt.NoFocus
                                onClicked: tunnelRow.clicked()
                            }
                        }
                    }
                }

                // Tailscale's own fix for its "Access denied", offered where it was refused.
                Revealer {
                    vertical: true
                    reveal: Vpn.needsOperator
                    Layout.fillWidth: true

                    Card {
                        width: parent.width
                        TunnelRow {
                            first: true
                            last: true
                            symbol: "admin_panel_settings"
                            name: Translation.tr("Allow Tailscale control")
                            note: Vpn.pending["operator"] ? Translation.tr("Waiting for your password…")
                                : Translation.tr("Asks for your password once")
                            selected: true
                            onClicked: if (!Vpn.pending["operator"]) Vpn.allowOperator()
                        }
                    }
                }

                Revealer {
                    vertical: true
                    reveal: root.exitNodesShown
                    Layout.fillWidth: true

                    ColumnLayout {
                        width: parent.width
                        spacing: 8

                        WindowDialogSectionHeader {
                            Layout.topMargin: 0
                            text: Translation.tr("Exit node")
                        }

                        Card {
                            TunnelRow {
                                first: true
                                last: (root.ts?.exitNodes.length ?? 0) === 0
                                symbol: "public_off"
                                name: Translation.tr("None")
                                note: Translation.tr("Only Tailscale traffic uses the tunnel")
                                selected: !root.ts?.exitNode
                                active: selected
                                onClicked: Vpn.setExitNode("")

                                Check {
                                    shown: !root.ts?.exitNode
                                }
                            }

                            Repeater {
                                model: ScriptModel {
                                    objectProp: "id"
                                    values: root.ts?.exitNodes ?? []
                                }
                                delegate: TunnelRow {
                                    id: nodeRow
                                    required property var modelData
                                    required property int index
                                    readonly property var n: root.ts?.exitNodes.find(x => x.id === modelData.id) ?? modelData
                                    last: index === (root.ts?.exitNodes.length ?? 0) - 1
                                    symbol: "public"
                                    name: n.name
                                    note: !n.online ? Translation.tr("Offline") : (n.place || Translation.tr("Sends all traffic through %1").arg(n.name))
                                    selected: n.active
                                    active: n.active
                                    // Offline is "can't" (TASTE 3.6); the row says why.
                                    enabled: n.online || n.active
                                    onClicked: Vpn.setExitNode(n.ip)

                                    Check {
                                        shown: nodeRow.n.active
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Import file")
            enabled: !Vpn.pending["import"]
            onClicked: Vpn.importFile()
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }

    // The DNS dialog's list card and row.
    component Card: Rectangle {
        default property alias rows: cardColumn.data
        Layout.fillWidth: true
        implicitHeight: cardColumn.implicitHeight
        radius: Appearance.rounding.large
        color: Appearance.colors.colSurfaceContainerHigh

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            spacing: 0
        }
    }

    component TunnelRow: DialogListItem {
        id: row
        property bool first: false
        property bool last: false
        property string symbol
        property string name
        property string note
        property bool selected: false
        property bool noteError: false
        default property alias trailing: trailingRow.data

        Layout.fillWidth: true
        topLeftRadius: first ? Appearance.rounding.large : 0
        topRightRadius: topLeftRadius
        bottomLeftRadius: last ? Appearance.rounding.large : 0
        bottomRightRadius: bottomLeftRadius

        contentItem: RowLayout {
            spacing: 10
            MaterialSymbol {
                iconSize: Appearance.font.pixelSize.larger
                text: row.symbol
                color: row.selected ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    color: row.selected ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: row.name
                }
                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: row.noteError ? Appearance.colors.colError : Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: row.note
                }
            }
            RowLayout {
                id: trailingRow
                spacing: 0
            }
        }
    }

    // Colour alone is not enough on a greyscale wallpaper (the DNS dialog's check).
    // Faded, not hidden, so the text keeps its width.
    component Check: MaterialSymbol {
        property bool shown: false
        iconSize: Appearance.font.pixelSize.larger
        text: "check"
        color: Appearance.colors.colPrimary
        opacity: shown ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }
}
