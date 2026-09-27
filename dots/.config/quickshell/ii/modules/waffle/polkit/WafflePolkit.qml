pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

FullscreenPolkitWindow {
    id: root
    holdForExit: true
    contentComponent: Component {
        WPolkitContent {
            onClosed: root.release()
        }
    }
}
