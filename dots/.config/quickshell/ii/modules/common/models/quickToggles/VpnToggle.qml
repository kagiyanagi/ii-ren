import QtQuick
import qs.services
import qs.modules.common

QuickToggleModel {
    id: root
    name: Translation.tr("VPN")
    readonly property var up: Vpn.up
    readonly property var lead: root.up[0] ?? null
    readonly property bool connecting: root.up.some(t => t.state === "connecting") || Object.keys(Vpn.pending).length > 0
    statusText: Vpn.tunnels.length === 0 ? Translation.tr("Not set up")
        : root.connecting ? Translation.tr("Connecting…")
        : root.up.length > 1 ? Translation.tr("%1 connected").arg(root.up.length)
        : root.lead ? (root.lead.exitNode ? `${root.lead.name} · ${root.lead.exitNode}` : root.lead.name)
        : Translation.tr("Off")
    tooltipText: Vpn.tunnels.length === 0 ? Translation.tr("Add a WireGuard or OpenVPN file, or install Tailscale")
        : toggled ? Translation.tr("Disconnect %1").arg(root.up.map(t => t.name).join(", "))
        : Translation.tr("Connect a VPN")
    icon: toggled ? "vpn_lock" : "vpn_key"

    toggled: root.up.length > 0
    mainAction: () => Vpn.toggle()
    hasMenu: true
}
