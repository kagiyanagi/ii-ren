import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarDashboard.quickToggles
import qs
import QtQuick

QuickToggleButton {
    toggled: Network.hotspotToggled
    enabled: Network.hotspotSupported
    opacity: Network.hotspotSupported ? 1.0 : 0.4
    buttonIcon: !Network.hotspotSupported ? "wifi_tethering_off" : (toggled ? "wifi_tethering" : "wifi_tethering_off")
    onClicked: Network.toggleHotspot()
    StyledToolTip {
        text: !Network.hotspotSupported
            ? Translation.tr("Wi-Fi adapter does not support AP mode")
            : toggled
                ? Translation.tr("Hotspot active: %1").arg(Network.hotspotSsid || Network.hotspotName)
                : Translation.tr("Turn on Wi-Fi hotspot")
    }
}
