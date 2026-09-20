import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.models

TabBar {
    id: root
    property real indicatorPadding: 8
    Layout.fillWidth: true

    background: Item {
        WheelHandler {
            onWheel: (event) => {
                if (event.angleDelta.y < 0) root.incrementCurrentIndex();
                else if (event.angleDelta.y > 0) root.decrementCurrentIndex();
            }
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        }

        Rectangle {
            id: activeIndicator
            z: 9999
            anchors.bottom: parent.bottom
            topLeftRadius: height
            topRightRadius: height
            bottomLeftRadius: 0
            bottomRightRadius: 0
            color: Appearance.colors.colPrimary
            // DESIGN.md 9: the indicator moves on elementMoveSmall, with the
            // trailing edge on the default spatial spec so the bar stretches
            // toward the new tab instead of sliding rigidly. The shared model's
            // own 100/300 defaults are neither token.
            property real baseWidth: root.count > 0 ? root.width / root.count : 0
            AnimatedTabIndexPair {
                id: idxPair
                idx1Duration: Appearance.animation.elementMoveSmall.duration
                idx2Duration: Appearance.animation.elementMove.duration
                index: root.currentIndex
            }
            height: 3
            x: Math.min(idxPair.idx1, idxPair.idx2) * baseWidth + root.indicatorPadding
            width: ((Math.max(idxPair.idx1, idxPair.idx2) + 1) * baseWidth - root.indicatorPadding) - x
        }

        // The active indicator's track, not a section divider: M3's tab anatomy
        // draws the full-width line the indicator rides on, and 5.5 is about
        // separators between content groups. It stays 1px colOutlineVariant.
        Rectangle {
            id: tabBarBottomBorder
            z: 9998
            anchors.bottom: parent.bottom
            height: 1
            anchors {
                left: parent.left
                right: parent.right
            }
            color: Appearance.colors.colOutlineVariant
        }
    }
}
