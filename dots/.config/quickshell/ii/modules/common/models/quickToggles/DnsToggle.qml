import QtQuick
import qs.services
import qs.modules.common

QuickToggleModel {
    id: root
    name: Translation.tr("DNS")
    readonly property string providerName: Dns.provider === "custom" ? Translation.tr("Custom")
        : (Dns.providers.find(p => p.id === Dns.provider)?.name ?? Translation.tr("Automatic"))
    statusText: !available ? Translation.tr("Not connected")
        : Dns.encrypted ? Translation.tr("%1 · Encrypted").arg(root.providerName)
        : root.providerName
    tooltipText: !available ? Translation.tr("Connect to a network to set its DNS")
        : toggled ? Translation.tr("DNS: %1 (%2)").arg(root.providerName).arg(Dns.servers)
        : Translation.tr("Using the network's DNS")
    icon: toggled ? "dns" : "language"

    available: Dns.available
    toggled: Dns.provider !== "auto"
    mainAction: () => Dns.toggle()
    hasMenu: true
}
