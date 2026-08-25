pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One notification mirrored from the phone. Expands to reveal the notification's
 * own actions and its reply box - collapsed, it is two lines like the phone's
 * own shade.
 */
Rectangle {
    id: root
    required property var modelData
    property bool expanded: false

    readonly property bool canReply: (root.modelData?.replyId ?? "") !== ""
    readonly property var actions: root.modelData?.actions ?? []
    readonly property bool hasDetail: root.canReply || root.actions.length > 0

    Layout.fillWidth: true
    implicitHeight: notificationColumn.implicitHeight + 20
    radius: Appearance.rounding.normal
    color: hoverHandler.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2

    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    Behavior on implicitHeight { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }

    HoverHandler { id: hoverHandler }
    TapHandler {
        enabled: root.hasDetail
        onTapped: root.expanded = !root.expanded
    }

    ColumnLayout {
        id: notificationColumn
        anchors {
            fill: parent
            margins: 10
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            NotificationAppIcon {
                Layout.alignment: Qt.AlignTop
                implicitSize: 34
                appIcon: AppSearch.guessIcon(root.modelData?.appName ?? "")
                summary: root.modelData?.title ?? ""
                image: (root.modelData?.iconPath ?? "") !== "" ? `file://${root.modelData.iconPath}` : ""
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        text: root.modelData?.appName ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colPrimary
                        elide: Text.ElideRight
                        Layout.maximumWidth: parent.width * 0.6
                    }
                    Item { Layout.fillWidth: true }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.modelData?.title ?? ""
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.modelData?.text ?? ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                    maximumLineCount: root.expanded ? 8 : 2
                    elide: Text.ElideRight
                }
            }

            RippleButton {
                Layout.alignment: Qt.AlignTop
                visible: root.modelData?.dismissable ?? false
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                onClicked: KdeConnectService.dismissNotification(root.modelData.id)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
            }
        }

        Flow { // Notification's own actions
            Layout.fillWidth: true
            visible: root.expanded && root.actions.length > 0
            spacing: 6
            Repeater {
                model: root.actions
                RippleButtonWithIcon {
                    id: actionButton
                    required property string modelData
                    materialIcon: "touch_app"
                    mainText: actionButton.modelData
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    onClicked: KdeConnectService.runNotificationAction(root.modelData.id, actionButton.modelData)
                }
            }
        }

        RowLayout { // Inline reply
            Layout.fillWidth: true
            visible: root.expanded && root.canReply
            spacing: 6

            MaterialTextField {
                id: replyField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Reply…")
                onAccepted: sendReply()
                function sendReply() {
                    if (text.trim() === "") return;
                    KdeConnectService.replyToNotification(root.modelData.replyId, text);
                    text = "";
                    root.expanded = false;
                }
            }
            RippleButton {
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                onClicked: replyField.sendReply()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "send"
                    iconSize: Appearance.font.pixelSize.normal
                    fill: 1
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }
}
