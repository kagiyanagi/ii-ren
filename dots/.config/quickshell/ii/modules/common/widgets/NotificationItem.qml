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
    property bool onlyNotification: false
    property real fontSize: Appearance.font.pixelSize.small
    property real padding: onlyNotification ? 0 : 8
    property real summaryElideRatio: 0.85

    implicitHeight: background.implicitHeight

    TextMetrics {
        id: summaryTextMetrics
        font.pixelSize: root.fontSize
        text: root.notificationObject.summary || ""
    }

    SwipeDismissible { // Drag manager
        id: dragManager
        owner: root
        target: background
        itemIndex: root.index ?? root.parent.children.indexOf(root)
        dismissOvershoot: notificationIcon.implicitWidth + 20 // Account for gaps and bouncy animations

        anchors.fill: root
        anchors.leftMargin: root.expanded ? -notificationIcon.implicitWidth : 0
        interactive: expanded
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onDismissed: Notifications.discardNotification(root.notificationObject.notificationId)
    }

    NotificationAppIcon { // App icon
        id: notificationIcon
        opacity: (!onlyNotification && notificationObject.image != "" && expanded) ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        image: notificationObject.image
        anchors.right: background.left
        anchors.top: background.top
        anchors.rightMargin: 10
    }

    Rectangle { // Background of notification item
        id: background
        width: parent.width
        anchors.left: parent.left
        radius: Appearance.rounding.small
        anchors.leftMargin: dragManager.xOffset

        Behavior on anchors.leftMargin {
            enabled: !dragManager.dragging
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }

        color: (expanded && !onlyNotification) ? 
            (notificationObject.urgency == NotificationUrgency.Critical) ? 
                ColorUtils.mix(Appearance.colors.colSecondaryContainer, Appearance.colors.colLayer2, 0.35) :
                (Appearance.colors.colLayer3) :
            ColorUtils.transparentize(Appearance.colors.colLayer3)

        implicitHeight: expanded ? (contentColumn.implicitHeight + padding * 2) : summaryRow.implicitHeight
        Behavior on implicitHeight {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout { // Content column
            id: contentColumn
            anchors.fill: parent
            anchors.margins: expanded ? root.padding : 0
            spacing: 3

            Behavior on anchors.margins {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            RowLayout { // Summary row
                id: summaryRow
                visible: !root.onlyNotification || !root.expanded
                Layout.fillWidth: true
                implicitHeight: summaryText.implicitHeight
                StyledText {
                    id: summaryText
                    Layout.fillWidth: summaryTextMetrics.width >= summaryRow.implicitWidth * root.summaryElideRatio
                    visible: !root.onlyNotification
                    font.pixelSize: root.fontSize
                    color: Appearance.colors.colOnLayer3
                    elide: Text.ElideRight
                    text: root.notificationObject.summary || ""
                }
                StyledText {
                    opacity: !root.expanded ? 1 : 0
                    visible: opacity > 0
                    Layout.fillWidth: true
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    font.pixelSize: root.fontSize
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap // Needed for proper eliding????
                    maximumLineCount: 1
                    textFormat: Text.StyledText
                    text: {
                        return NotificationUtils.processNotificationBody(notificationObject.body, notificationObject.appName || notificationObject.summary).replace(/\n/g, "<br/>")
                    }
                }
            }

            ColumnLayout { // Expanded content
                id: expandedContentColumn
                Layout.fillWidth: true
                opacity: root.expanded ? 1 : 0
                visible: opacity > 0

                StyledText { // Notification body (expanded)
                    id: notificationBodyText
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Layout.fillWidth: true
                    font.pixelSize: root.fontSize
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    textFormat: Text.RichText
                    text: {
                        return `<style>img{max-width:${expandedContentColumn.width}px;}</style>` + 
                            `${NotificationUtils.processNotificationBody(notificationObject.body, notificationObject.appName || notificationObject.summary).replace(/\n/g, "<br/>")}`
                    }

                    onLinkActivated: (link) => {
                        Qt.openUrlExternally(link)
                        GlobalStates.sidebarRightOpen = false
                    }
                    
                    PointingHandLinkHover {}
                }

                Item {
                    Layout.fillWidth: true
                    implicitWidth: actionsFlickable.implicitWidth
                    implicitHeight: actionsFlickable.implicitHeight

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: actionsFlickable.width
                            height: actionsFlickable.height
                            radius: Appearance.rounding.small
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

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on height {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
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
}
