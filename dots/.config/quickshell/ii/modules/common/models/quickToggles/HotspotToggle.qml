import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("Hotspot")
    statusText: !available
        ? Translation.tr("Unsupported")
        : toggled
            ? (Network.hotspotSsid || Network.hotspotName || Translation.tr("Active"))
            : Translation.tr("Off")
    tooltipText: !available
        ? Translation.tr("Wi-Fi adapter does not support AP mode")
        : toggled
            ? Translation.tr("Hotspot active: %1").arg(Network.hotspotSsid || Network.hotspotName)
            : Translation.tr("Turn on Wi-Fi hotspot")
    icon: !available
        ? "wifi_tethering_off"
        : (toggled ? "wifi_tethering" : "wifi_tethering_off")

    available: Network.hotspotSupported
    toggled: Network.hotspotToggled
    mainAction: () => Network.toggleHotspot()
    hasMenu: true
}
