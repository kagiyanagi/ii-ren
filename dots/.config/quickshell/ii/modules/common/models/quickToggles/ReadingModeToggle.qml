import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    property bool auto: HyprlandReadingMode.automatic

    name: Translation.tr("Reading mode")
    statusText: (auto ? Translation.tr("Auto, ") : "") + (toggled ? Translation.tr("Active") : Translation.tr("Inactive"))

    toggled: HyprlandReadingMode.manualEnable
    icon: auto ? "auto_mode" : "menu_book"
    
    mainAction: () => {
        HyprlandReadingMode.toggleManual(!HyprlandReadingMode.manualEnable)
    }
    hasMenu: true

    tooltipText: Translation.tr("Reading mode | Right-click to configure")
}
