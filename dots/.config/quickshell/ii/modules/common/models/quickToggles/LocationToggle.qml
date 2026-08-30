import QtQuick
import qs.modules.common
import qs.services
import Quickshell.Io

QuickToggleModel {
    id: root
    name: Translation.tr("Location")
    icon: root.toggled ? "location_on" : "location_disabled"
    tooltipText: Translation.tr("GeoClue location service")

    available: LocationService.available
    toggled: LocationService.enabled
    mainAction: () => LocationService.toggle()
}
