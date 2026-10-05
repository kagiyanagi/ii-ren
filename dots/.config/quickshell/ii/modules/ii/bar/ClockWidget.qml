import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    readonly property bool showDate: (Config.options.bar.clock.showDate ?? true) && Config.options.bar.verbose
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
    readonly property string dateFormat: (Config.options.bar.clock.dateFormat && Config.options.bar.clock.dateFormat.trim().length > 0)
        ? Config.options.bar.clock.dateFormat
        : (Config.options?.time?.dateFormat ?? "ddd, dd/MM")

    readonly property string formattedTime: Qt.locale().toString(DateTime.clock.date, root.timeFormat)
    readonly property string formattedDate: Qt.locale().toString(DateTime.clock.date, root.dateFormat)

    implicitWidth: rowLayout.implicitWidth + rowLayout.spacing * 10
    implicitHeight: Appearance.sizes.barHeight
    property color colText: dropArea.containsDrag ? Appearance.colors.colPrimary : rootItem.highlighted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1

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

    // The same state film as Resources beside it, inside the BarGroup's inset.
    StateOverlay {
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        radius: Appearance.rounding.full
        contentColor: rootItem.highlighted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
        hover: mouseArea.containsMouse
        press: mouseArea.pressed
    }

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        spacing: 4

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.large
            color: root.colText
            text: root.formattedTime
        }

        StyledText {
            visible: root.showDate && root.formattedDate.length > 0
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.colText
            text: "•"
        }

        StyledText {
            visible: root.showDate && root.formattedDate.length > 0
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.colText
            text: root.formattedDate
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

        ClockWidgetPopup {
            hoverTarget: mouseArea
        }
    }
}
