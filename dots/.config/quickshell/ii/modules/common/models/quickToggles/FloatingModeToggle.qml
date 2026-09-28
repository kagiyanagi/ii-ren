import QtQuick
import qs.services

QuickToggleModel {
    name: Translation.tr("Floating windows")
    toggled: FloatingMode.enabled
    icon: "stack"

    mainAction: () => {
        FloatingMode.toggle()
    }

    tooltipText: Translation.tr("Float every window, with controls beside the ones that have none")
}
