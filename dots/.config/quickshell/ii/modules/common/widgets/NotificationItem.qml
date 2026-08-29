import qs
import qs.modules.common
import qs.services
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications

Item { // Notification item area
    id: root
    property var notificationObject
    property bool expanded: false
    property real fontSize: Appearance.font.pixelSize.small

    implicitHeight: background.implicitHeight

    SwipeDismissible { // Drag manager
        id: dragManager
        owner: root
        target: background
        itemIndex: root.index ?? root.parent.children.indexOf(root)

        anchors.fill: root
        interactive: expanded
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onDismissed: Notifications.discardNotification(root.notificationObject.notificationId)
    }

    Item { // Slides on swipe
        id: background
        width: parent.width
        anchors.left: parent.left
        anchors.leftMargin: dragManager.xOffset
        implicitHeight: contentColumn.implicitHeight

        Behavior on anchors.leftMargin {
            enabled: !dragManager.dragging
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
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
                    spacing: 1

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
                        visible: text.length > 0
                        Layout.fillWidth: true
                        font.pixelSize: root.fontSize
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap // Needed for proper eliding????
                        elide: Text.ElideRight
                        maximumLineCount: root.expanded ? 20 : 1
                        textFormat: root.expanded ? Text.RichText : Text.StyledText
                        text: {
                            const body = NotificationUtils.processNotificationBody(notificationObject.body, notificationObject.appName || notificationObject.summary).replace(/\n/g, "<br/>")
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
                Layout.fillWidth: true
                opacity: root.expanded ? 1 : 0
                visible: opacity > 0
                implicitWidth: actionsFlickable.implicitWidth
                implicitHeight: actionsFlickable.implicitHeight

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

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
                }

                StyledFlickable { // Notification actions
                    id: actionsFlickable
                    anchors.fill: parent
                    implicitHeight: actionRowLayout.implicitHeight
                    contentWidth: actionRowLayout.implicitWidth

                    Behavior on implicitHeight {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    RowLayout {
                        id: actionRowLayout
                        Layout.alignment: Qt.AlignBottom

                        NotificationActionButton {
                            Layout.fillWidth: true
                            buttonText: Translation.tr("Close")
                            urgency: notificationObject.urgency
                            implicitWidth: (notificationObject.actions.length == 0) ? ((actionsFlickable.width - actionRowLayout.spacing) / 2) :
                                (contentItem.implicitWidth + leftPadding + rightPadding)

                            onClicked: {
                                dragManager.destroyWithAnimation()
                            }

                            contentItem: MaterialSymbol {
                                iconSize: Appearance.font.pixelSize.larger
                                horizontalAlignment: Text.AlignHCenter
                                color: (notificationObject.urgency == NotificationUrgency.Critical) ?
                                    Appearance.m3colors.m3onSurfaceVariant : Appearance.m3colors.m3onSurface
                                text: "close"
                            }
                        }

                        Repeater {
                            id: actionRepeater
                            model: notificationObject.actions
                            NotificationActionButton {
                                id: notifAction
                                required property var modelData
                                Layout.fillWidth: true
                                buttonText: modelData.text
                                urgency: notificationObject.urgency
                                onClicked: {
                                    Notifications.attemptInvokeAction(notificationObject.notificationId, modelData.identifier);
                                }
                            }
                        }

                        NotificationActionButton {
                            Layout.fillWidth: true
                            urgency: notificationObject.urgency
                            implicitWidth: (notificationObject.actions.length == 0) ? ((actionsFlickable.width - actionRowLayout.spacing) / 2) :
                                (contentItem.implicitWidth + leftPadding + rightPadding)

                            onClicked: {
                                Quickshell.clipboardText = notificationObject.body
                                copyIcon.text = "inventory"
                                copyIconTimer.restart()
                            }

                            Timer {
                                id: copyIconTimer
                                interval: 1500
                                repeat: false
                                onTriggered: {
                                    copyIcon.text = "content_copy"
                                }
                            }

                            contentItem: MaterialSymbol {
                                id: copyIcon
                                iconSize: Appearance.font.pixelSize.larger
                                horizontalAlignment: Text.AlignHCenter
                                color: (notificationObject.urgency == NotificationUrgency.Critical) ?
                                    Appearance.m3colors.m3onSurfaceVariant : Appearance.m3colors.m3onSurface
                                text: "content_copy"
                            }
                        }

                    }
                }
            }
        }
    }
}
