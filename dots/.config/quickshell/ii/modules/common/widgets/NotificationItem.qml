pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.services
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Services.Notifications

Item { // Notification item area
    id: root
    property var notificationObject
    property bool expanded: false
    property real fontSize: Appearance.font.pixelSize.small
    // The row's index in the group's list, passed down rather than read off
    // `parent.children`: SwipeDismissible nudges the neighbouring rows by it.
    property int itemIndex: -1
    // The card this row is drawn on. ScrollEdgeFade ramps from an opaque copy of
    // it to transparent, so a wrong one shows as a band of the wrong layer (6.1).
    property color surfaceColor: Appearance.colors.colLayer2

    implicitHeight: background.implicitHeight

    SwipeDismissible { // Drag manager
        id: dragManager
        owner: root
        target: background
        itemIndex: root.itemIndex

        anchors.fill: root
        // The group swipes as one until it is expanded, then each row does.
        interactive: root.expanded
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onDismissed: Notifications.discardNotification(root.notificationObject.notificationId)
    }

    Item { // Slides on swipe
        id: background
        width: parent.width
        anchors.left: parent.left
        anchors.leftMargin: dragManager.xOffset
        implicitHeight: contentColumn.implicitHeight

        // The snap back after a released swipe: spatial, and on one spec rather
        // than elementMove's duration wearing the fast curve.
        Behavior on anchors.leftMargin {
            enabled: !dragManager.dragging
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            id: contentColumn
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            spacing: 10

            RowLayout { // Title and text, with the large icon beside them
                Layout.fillWidth: true
                spacing: 12

                ColumnLayout {
                    id: textColumn
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText { // Title
                        Layout.fillWidth: true
                        font.pixelSize: root.fontSize
                        font.variableAxes: Appearance.font.variableAxes.title
                        color: Appearance.colors.colOnLayer2
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        text: root.notificationObject.summary || ""
                    }

                    StyledText { // Text
                        id: notificationBodyText
                        visible: notificationBodyText.text.length > 0
                        Layout.fillWidth: true
                        font.pixelSize: root.fontSize
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap // Needed for proper eliding????
                        elide: Text.ElideRight
                        maximumLineCount: root.expanded ? 20 : 1
                        textFormat: root.expanded ? Text.RichText : Text.StyledText
                        text: {
                            const body = NotificationUtils.processNotificationBody(root.notificationObject.body, root.notificationObject.appName || root.notificationObject.summary).replace(/\n/g, "<br/>")
                            return root.expanded ? `<style>img{max-width:${textColumn.width}px;}</style>${body}` : body
                        }

                        onLinkActivated: (link) => {
                            Qt.openUrlExternally(link)
                            GlobalStates.sidebarRightOpen = false
                        }

                        PointingHandLinkHover {}
                    }
                }

                Loader { // Large icon, Android puts it opposite the text
                    Layout.alignment: Qt.AlignTop
                    active: root.notificationObject.image != ""
                    sourceComponent: NotificationAppIcon {
                        implicitSize: 40
                        image: root.notificationObject.image
                    }
                }
            }

            Item { // Actions
                id: actionsArea
                Layout.fillWidth: true
                implicitWidth: actionsFlickable.implicitWidth
                implicitHeight: actionsFlickable.implicitHeight

                // Entering is the slower effects spec and leaving the fast one
                // (2.5). The spec is set from inside the binding that writes
                // opacity, because a Behavior bakes its duration when that write
                // happens and a sibling binding on `expanded` is not necessarily
                // current yet (2.9).
                property AnimSpec fadeSpec: Appearance.animation.elementMoveFast
                opacity: {
                    actionsArea.fadeSpec = root.expanded ?
                        Appearance.animation.elementMoveFast : Appearance.animation.elementMoveExit
                    return root.expanded ? 1 : 0
                }
                visible: actionsArea.opacity > 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: actionsArea.fadeSpec.duration
                        easing.type: actionsArea.fadeSpec.type
                        easing.bezierCurve: actionsArea.fadeSpec.bezierCurve
                    }
                }

                // design-ok: StyledFlickable does not clip, so this is the only
                // thing keeping an action pill inside the card, and it has to be
                // round to match them. Only an expanded row renders it.
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: actionsFlickable.width
                        height: actionsFlickable.height
                        radius: Appearance.rounding.full
                    }
                }

                ScrollEdgeFade {
                    target: actionsFlickable
                    vertical: false
                    color: root.surfaceColor
                }

                StyledFlickable { // Notification actions
                    id: actionsFlickable
                    anchors.fill: parent
                    implicitHeight: actionRowLayout.implicitHeight
                    contentWidth: actionRowLayout.implicitWidth

                    Behavior on implicitHeight {
                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                    }

                    RowLayout {
                        id: actionRowLayout
                        Layout.alignment: Qt.AlignBottom
                        spacing: 4 // 5.3: items in a chip row sit 4-6 apart

                        NotificationActionButton {
                            id: closeButton
                            Layout.fillWidth: true
                            buttonText: Translation.tr("Close")
                            urgency: root.notificationObject.urgency
                            implicitWidth: (root.notificationObject.actions.length == 0) ? ((actionsFlickable.width - actionRowLayout.spacing) / 2) :
                                (closeButton.contentItem.implicitWidth + closeButton.leftPadding + closeButton.rightPadding)

                            onClicked: {
                                dragManager.destroyWithAnimation()
                            }

                            contentItem: MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.larger
                                horizontalAlignment: Text.AlignHCenter
                                color: closeButton.colContent
                                text: "close"
                            }
                        }

                        Repeater {
                            id: actionRepeater
                            model: root.notificationObject.actions
                            NotificationActionButton {
                                id: notifAction
                                required property var modelData
                                Layout.fillWidth: true
                                buttonText: notifAction.modelData.text
                                urgency: root.notificationObject.urgency
                                onClicked: {
                                    Notifications.attemptInvokeAction(root.notificationObject.notificationId, notifAction.modelData.identifier);
                                }
                            }
                        }

                        NotificationActionButton {
                            id: copyButton
                            Layout.fillWidth: true
                            urgency: root.notificationObject.urgency
                            implicitWidth: (root.notificationObject.actions.length == 0) ? ((actionsFlickable.width - actionRowLayout.spacing) / 2) :
                                (copyButton.contentItem.implicitWidth + copyButton.leftPadding + copyButton.rightPadding)

                            onClicked: {
                                Quickshell.clipboardText = root.notificationObject.body
                                copyIcon.text = "inventory"
                                copyIconTimer.restart()
                            }

                            Timer {
                                id: copyIconTimer
                                interval: 1500 // How long the copied tick stays up, not an animation
                                repeat: false
                                onTriggered: {
                                    copyIcon.text = "content_copy"
                                }
                            }

                            contentItem: MaterialSymbol {
                                id: copyIcon
                                iconSize: Appearance.font.pixelSize.larger
                                horizontalAlignment: Text.AlignHCenter
                                color: copyButton.colContent
                                text: "content_copy"
                            }
                        }

                    }
                }
            }
        }
    }
}
