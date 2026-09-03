pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

/**
 * The shelf: the row of app icons that stands in for notifications the stack is
 * not showing as cards.
 *
 * AOSP's `NotificationShelf` holds "overflow icons that don't fit into the
 * regular list anymore" and is 48 tall (`notification_shelf_height`). It is the
 * whole point of the Android 16 lock screen's default compact view - one
 * notification in full, everything else reduced to its icon underneath - and
 * NotificationStackSizeCalculator's `maxKeyguardNotifications` is what decides
 * where the cards stop and the shelf starts.
 */
Item {
    id: root

    property var groups: []
    property string hoverTarget: ""
    property string pressTarget: ""
    property color colContent: Appearance.colors.colOnSurface

    // Past this the tail stops reading as a row and starts reading as clutter;
    // the remainder becomes a count, the way AOSP's overflow number does.
    readonly property int maxIcons: 8
    readonly property var shown: (root.groups ?? []).slice(0, root.maxIcons)
    readonly property int hiddenCount: Math.max(0, (root.groups?.length ?? 0) - root.shown.length)

    // Shelf icons are status-bar sized, not the card's 40.
    readonly property real iconSize: 20

    implicitWidth: iconRow.width
    // notification_shelf_height
    implicitHeight: 48

    function hitTest(px: real, py: real): string {
        if (px < 0 || py < 0 || px > root.width || py > root.height)
            return "";
        return "shelf";
    }

    // AOSP brings the shelf in with `shelf_appear_translation` (42) of vertical
    // travel; enter decelerating, and the exit is the view's business.
    property real appearProgress: 0
    Component.onCompleted: root.appearProgress = 1
    Behavior on appearProgress {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(root)
    }

    Item {
        id: shelfContent
        anchors.fill: parent
        opacity: root.appearProgress
        transform: Translate {
            y: 42 * (1 - root.appearProgress)
        }

        Row {
            id: iconRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Repeater {
                model: root.shown

                delegate: Item {
                    id: shelfIcon
                    required property var modelData

                    width: root.iconSize
                    height: root.iconSize
                    opacity: (root.hoverTarget === "shelf" || root.pressTarget === "shelf") ? 1 : 0.85

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(shelfIcon)
                    }

                    NotificationAppIcon {
                        anchors.fill: parent
                        implicitSize: root.iconSize
                        materialIconScale: 0.62
                        appIconScale: 0.9
                        appIcon: shelfIcon.modelData?.appIcon ?? ""
                        summary: shelfIcon.modelData?.notifications?.[0]?.summary ?? ""
                        urgency: NotificationUrgency.Normal
                    }
                }
            }

            StyledText { // AOSP's group_overflow_number, for the tail
                anchors.verticalCenter: parent.verticalCenter
                visible: root.hiddenCount > 0
                leftPadding: 4
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.colContent
                text: `+${root.hiddenCount}`
            }
        }
    }
}
