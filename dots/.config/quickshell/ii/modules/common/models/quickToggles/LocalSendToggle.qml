import QtQuick
import Quickshell
import qs
import qs.services

// On/off only: an incoming transfer is accepted or denied from its notification.
QuickToggleModel {
    name: Translation.tr("LocalSend")
    available: LocalSend.available
    toggled: LocalSend.enabled
    icon: "devices"

    mainAction: () => {
        if (LocalSend.enabled) LocalSend.stopServer()
        else LocalSend.startServer()
    }

    altAction: () => {
        Quickshell.execDetached(["localsend"])
        GlobalStates.sidebarRightOpen = false
    }

    tooltipText: Translation.tr("Receive files from LocalSend devices on the network | Right-click to open LocalSend")
}
