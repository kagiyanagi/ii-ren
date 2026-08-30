import qs.modules.common.widgets
import qs.services

QuickToggleButton {
    id: root
    toggled: Idle.inhibit
    buttonIcon: "local_cafe"
    onClicked: {
        Idle.toggleInhibit()
    }
    StyledToolTip {
        text: Translation.tr("Keep system awake")
    }

}
