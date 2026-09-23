import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Wayland

FullscreenPolkitWindow {
    id: root
    holdForExit: true
    contentComponent: Component {
        PolkitContent {
            onClosed: root.release()
        }
    }
}
