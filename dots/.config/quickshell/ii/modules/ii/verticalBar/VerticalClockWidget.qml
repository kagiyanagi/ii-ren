import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.ii.bar as Bar

Item {
    id: root
    implicitHeight: clockColumn.implicitHeight + 10
    implicitWidth: Appearance.sizes.verticalBarWidth

    Connections {
        target: LocalSend
        function onCurrentTransferChanged() {
            if (LocalSend.currentTransfer) {
                rootItem.toggleHighlight(true)
            } else {
                rootItem.toggleHighlight(false)
            }
        }
        function onDroppedFilesChanged() {
            if (LocalSend.droppedFiles.length > 0) {
                rootItem.toggleHighlight(true)
            } else {
                rootItem.toggleHighlight(false)
            }
        }
    }

    readonly property string timeFormat: {
        if (Config.options.bar.clock.timeFormat && Config.options.bar.clock.timeFormat.trim().length > 0) {
            return Config.options.bar.clock.timeFormat;
        }
        let base = Config.options?.time?.format ?? "hh:mm";
        if (Config.options.bar.clock.showSeconds && !base.includes("s")) {
            if (base.includes("ap")) return base.replace("ap", ":ss ap");
            if (base.includes("AP")) return base.replace("AP", ":ss AP");
            return base + ":ss";
        }
        return base;
    }
    readonly property string formattedTime: Qt.locale().toString(DateTime.clock.date, root.timeFormat)

    ColumnLayout {
        id: clockColumn
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: root.formattedTime.split(/[: ]/).filter(item => item.length > 0)
            delegate: StyledText {
                required property string modelData
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: modelData.match(/am|pm/i) ? 
                    Appearance.font.pixelSize.smaller // Smaller "am"/"pm" text
                    : Appearance.font.pixelSize.large
                color: dropArea.containsDrag ? Appearance.colors.colPrimary : rootItem.highlighted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                text: modelData.length <= 2 ? modelData.padStart(2, "0") : modelData
            }
        }
    }

    DropArea {
        id: dropArea
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: (drop) => {
            if (!drop.hasUrls) return
            for (let i = 0; i < drop.urls.length; i++)
                LocalSend.addDroppedFile(drop.urls[i])
            drop.accept(Qt.CopyAction)
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow

        Bar.ClockWidgetPopup {
            compact: Config.options.bar.tooltips.compactPopups
            hoverTarget: mouseArea
        }
    }
}