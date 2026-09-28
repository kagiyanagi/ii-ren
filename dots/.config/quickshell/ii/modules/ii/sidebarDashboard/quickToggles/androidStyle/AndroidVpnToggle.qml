import QtQuick
import qs
import qs.services
import qs.modules.common.models.quickToggles

AndroidQuickToggleButton {
    id: root
    toggleModel: VpnToggle {}
    // Nothing a tap could pick (none set up, or several and none used yet) opens the list.
    mainAction: () => {
        if (!toggleModel.mainAction()) root.openMenu();
    }

    // A tile has no room for "Access denied" or "Needs a password": the dialog does.
    Connections {
        target: Vpn
        function onFailed() {
            if (GlobalStates.sidebarRightOpen) root.openMenu();
        }
    }
}
