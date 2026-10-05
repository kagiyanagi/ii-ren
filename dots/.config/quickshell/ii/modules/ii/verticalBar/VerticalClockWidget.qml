import qs.modules.common
import qs.modules.common.functions
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

    // The same state film as Resources beside it, inside the BarGroup's inset.
    StateOverlay {
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        radius: Appearance.rounding.full
        contentColor: rootItem.highlighted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
        hover: mouseArea.containsMouse
        press: mouseArea.pressed
    }

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
                color: dropArea.containsDrag ? Appearance.colors.colPrimary : rootItem.highlighted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
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
        // Only a click with somewhere to go looks clickable; click-to-show owns the click.
        cursorShape: Config.options.bar.clickActions.clock ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (!Config.options.bar.tooltips.clickToShow) Session.barClick("clock")

        Bar.ClockWidgetPopup {
            hoverTarget: mouseArea
        }
    }
}