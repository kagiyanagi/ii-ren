import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles

AndroidQuickToggleButton {
    id: root

    readonly property string customId: root.buttonData?.id ?? ""
    readonly property var customData: CustomToggles.getToggle(root.customId)

    name: root.customData?.name ?? Translation.tr("Custom")
    buttonIcon: root.customData?.icon ?? "terminal"
    tooltipText: root.name
    hasMenu: true

    toggled: CustomToggles.isToggled(root.customId)
    statusText: root.toggled ? Translation.tr("Active") : Translation.tr("Inactive")

    mainAction: () => {
        CustomToggles.toggle(root.customId);
    }

    onOpenMenu: {
        if (root.chooser?.openEditCustomToggleDialog)
            root.chooser.openEditCustomToggleDialog(root.customId);
    }
}
