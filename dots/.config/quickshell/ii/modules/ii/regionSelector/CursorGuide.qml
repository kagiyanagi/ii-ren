import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Item {
    id: root
    property var action
    property var selectionMode

    readonly property var actionInfo: {
        switch (root.action) {
        case RegionSelection.SnipAction.Copy:
        case RegionSelection.SnipAction.Edit:
            return { symbol: "content_cut", description: Translation.tr("Copy region (LMB) or annotate (RMB)"), duration: 1000 };
        case RegionSelection.SnipAction.Search:
            return { symbol: "image_search", description: Translation.tr("Use Google Lens (LMB) or ask AI (RMB)"), duration: 1500 };
        case RegionSelection.SnipAction.CharRecognition:
            return { symbol: "document_scanner", description: Translation.tr("Recognize text"), duration: 1000 };
        case RegionSelection.SnipAction.Record:
        case RegionSelection.SnipAction.RecordWithSound:
            return { symbol: "videocam", description: Translation.tr("Record region"), duration: 1000 };
        default:
            return { symbol: "", description: "", duration: 1000 };
        }
    }
    property int duration: root.actionInfo.duration
    property string description: root.actionInfo.description
    property string materialSymbol: root.actionInfo.symbol

    property bool showDescription: true
    function hideDescription() {
        root.showDescription = false
    }
    Timer {
        id: descTimeout
        interval: root.duration
        running: true
        onTriggered: {
            root.hideDescription()
        }
    }
    onActionChanged: {
        root.showDescription = true
        descTimeout.restart()
    }

    property int margins: 8
    implicitWidth: content.implicitWidth + margins * 2
    implicitHeight: content.implicitHeight + margins * 2

    Rectangle {
        id: content
        anchors.centerIn: parent

        property real padding: 8
        implicitHeight: 38
        implicitWidth: root.showDescription ? contentRow.implicitWidth + padding * 2 : implicitHeight
        clip: true

        topLeftRadius: 6
        bottomLeftRadius: implicitHeight - topLeftRadius
        bottomRightRadius: bottomLeftRadius
        topRightRadius: bottomLeftRadius

        color: Appearance.colors.colPrimary

        Behavior on topLeftRadius {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        Behavior on implicitWidth {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        Row {
            id: contentRow
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
                leftMargin: content.padding
            }
            spacing: 12

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                iconSize: 22
                color: Appearance.colors.colOnPrimary
                animateChange: true
                text: root.materialSymbol
            }

            FadeLoader {
                id: descriptionLoader
                anchors.verticalCenter: parent.verticalCenter
                shown: root.showDescription
                sourceComponent: StyledText {
                    color: Appearance.colors.colOnPrimary
                    text: root.description
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                }
            }
        }
    }
}
