import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Item {
    id: root
    property var action

    readonly property var actionInfo: {
        switch (root.action) {
        case RegionSelection.SnipAction.Copy:
        case RegionSelection.SnipAction.Edit:
            return { symbol: "content_cut", description: Translation.tr("Copy region (LMB) or annotate (RMB)") };
        case RegionSelection.SnipAction.Search:
            return { symbol: "image_search", description: Translation.tr("Use Google Lens (LMB) or ask AI (RMB)") };
        case RegionSelection.SnipAction.CharRecognition:
            return { symbol: "document_scanner", description: Translation.tr("Recognize text") };
        case RegionSelection.SnipAction.QrScan:
            return { symbol: "qr_code_scanner", description: Translation.tr("Scan QR code") };
        case RegionSelection.SnipAction.Record:
        case RegionSelection.SnipAction.RecordWithSound:
            return { symbol: "videocam", description: Translation.tr("Record region") };
        default:
            return { symbol: "", description: "" };
        }
    }
    property string description: root.actionInfo.description
    property string materialSymbol: root.actionInfo.symbol

    // Shown until the first press, or for as long as a Toast.LENGTH_SHORT
    // (NotificationManagerService SHORT_DELAY): long enough to read one line.
    property bool showDescription: true
    function hideDescription() {
        root.showDescription = false
    }
    Timer {
        id: descTimeout
        interval: 2000
        running: true
        onTriggered: {
            root.hideDescription()
        }
    }
    // Another region keybind pressed while this one is open switches the action.
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

        // An icon button's height around the standard icon, and a chip's
        // asymmetry once it carries text: 8 before the icon, 16 after the label.
        readonly property real leadingPadding: 8
        readonly property real trailingPadding: 16
        implicitHeight: 40
        implicitWidth: root.showDescription ? contentRow.implicitWidth + leadingPadding + trailingPadding : implicitHeight
        clip: true

        // Pointed at the cursor it hangs from, round everywhere else.
        topLeftRadius: Appearance.rounding.unsharpenmore
        bottomLeftRadius: Appearance.rounding.full
        bottomRightRadius: Appearance.rounding.full
        topRightRadius: Appearance.rounding.full

        color: Appearance.colors.colPrimary

        Behavior on implicitWidth {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        Row {
            id: contentRow
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
                leftMargin: content.leadingPadding
            }
            spacing: 8

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                iconSize: 24
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
                }
            }
        }
    }
}
