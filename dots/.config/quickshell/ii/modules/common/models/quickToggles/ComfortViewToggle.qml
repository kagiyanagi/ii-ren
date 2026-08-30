import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    property bool auto: HyprlandComfortView.automatic

    name: Translation.tr("Comfort View")
    statusText: (auto ? Translation.tr("Auto, ") : "") + (toggled ? Translation.tr("Active") : Translation.tr("Inactive"))

    toggled: HyprlandComfortView.manualEnable
    icon: auto ? "auto_mode" : "visibility"
    
    mainAction: () => {
        HyprlandComfortView.toggleManual(!HyprlandComfortView.manualEnable)
    }
    hasMenu: true

    tooltipText: Translation.tr("Comfort View | Right-click to configure")
}
