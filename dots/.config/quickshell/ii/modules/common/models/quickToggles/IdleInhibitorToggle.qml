import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Keep awake")

    toggled: Idle.inhibit
    icon: toggled ? "kettle" : "local_cafe"
    statusText: !toggled ? ""
        : Idle.anchors.length === 1 ? Translation.tr("While %1 runs").arg(Idle.anchors[0].name)
        : Idle.anchors.length > 1 ? Translation.tr("While %1 apps run").arg(Idle.anchors.length)
        : Idle.until > 0 ? Translation.tr("%1 left").arg(Idle.remainingText)
        : Translation.tr("Always")
    mainAction: () => {
        Idle.toggleInhibit()
    }
    hasMenu: true
    tooltipText: Translation.tr("Keep system awake")
}
