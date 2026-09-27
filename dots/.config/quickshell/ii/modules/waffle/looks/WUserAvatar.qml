pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks

Item {
    id: root

    property alias source: avatar.source
    property alias fallbacks: avatar.fallbacks
    property alias sourceSize: avatar.sourceSize

    implicitWidth: 32
    implicitHeight: 32

    StyledImage {
        id: avatar
        anchors.fill: parent
        sourceSize: root.sourceSize
        source: Directories.userAvatarPathAccountsService
        fallbacks: [Directories.userAvatarPathRicersAndWeirdSystems, Directories.userAvatarPathRicersAndWeirdSystems2]

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Circle {
                diameter: Math.min(avatar.width, avatar.height)
            }
        }
    }
}
