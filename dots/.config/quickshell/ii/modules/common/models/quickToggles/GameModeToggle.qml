import QtQuick
import qs.services

QuickToggleModel {
    name: Translation.tr("Game mode")
    toggled: HyprlandGameMode.active
    icon: "gamepad"

    mainAction: () => {
        HyprlandGameMode.toggle();
    }

    tooltipText: Translation.tr("Game mode")
}
