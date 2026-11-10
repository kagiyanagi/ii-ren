import qs.modules.common
import qs.modules.common.widgets
import qs.services

QuickToggleButton {
    id: root
    toggled: HyprlandGameMode.active
    buttonIcon: "gamepad"

    onClicked: {
        HyprlandGameMode.toggle()
    }
    StyledToolTip {
        text: Translation.tr("Game mode")
    }
}
