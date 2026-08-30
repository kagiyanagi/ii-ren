import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Quickshell
import Quickshell.Io

QuickToggleModel {
    id: root
    name: Translation.tr("Cloudflare WARP")

    available: CloudflareWarpService.available
    toggled: CloudflareWarpService.connected
    icon: "cloud_lock"
    statusText: !available
        ? Translation.tr("Daemon stopped")
        : (toggled ? Translation.tr("Connected") : Translation.tr("Disconnected"))
    tooltipText: !available
        ? Translation.tr("Cloudflare WARP daemon is not running (sudo systemctl enable --now warp-svc)")
        : (toggled ? Translation.tr("Cloudflare WARP active (1.1.1.1)") : Translation.tr("Connect to Cloudflare WARP"))
    mainAction: () => CloudflareWarpService.toggle()
}
