import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    readonly property bool showDate: (Config.options.bar.clock.showDate ?? true) && Config.options.bar.verbose
    // Show seconds applies to a picked format too, not only the General one.
    readonly property string timeFormat: {
        const custom = Config.options.bar.clock.timeFormat?.trim();
        const base = custom || (Config.options?.time?.format ?? "hh:mm");
        if (!Config.options.bar.clock.showSeconds || base.includes("s"))
            return base;
        return base.includes("mm") ? base.replace("mm", "mm:ss") : base + ":ss";
    }
    readonly property string dateFormat: (Config.options.bar.clock.dateFormat && Config.options.bar.clock.dateFormat.trim().length > 0)
        ? Config.options.bar.clock.dateFormat
        : (Config.options?.time?.dateFormat ?? "ddd, dd/MM")

    readonly property string formattedTime: Qt.locale().toString(DateTime.clock.date, root.timeFormat)
    readonly property string formattedDate: Qt.locale().toString(DateTime.clock.date, root.dateFormat)

    // Material style draws the clock as its own pill (BarMaterialPill); a
    // LocalSend highlight turns the whole group colPrimary, so it falls back
    // to the plain row for that.
    readonly property bool material: Config.options.bar.barGroupStyle === 3 && !rootItem.highlighted
    implicitWidth: root.material ? (materialPill.item?.implicitWidth ?? 0) : rowLayout.implicitWidth + rowLayout.spacing * 10
    implicitHeight: Appearance.sizes.barHeight
    property color colText: dropArea.containsDrag ? Appearance.colors.colPrimary : rootItem.highlighted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1

    Connections {
        target: LocalSend
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
        visible: !root.material
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        radius: Appearance.rounding.full
        contentColor: rootItem.highlighted ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
        hover: mouseArea.containsMouse
        press: mouseArea.pressed
    }

    Loader {
        id: materialPill
        active: root.material
        anchors.centerIn: parent
        sourceComponent: BarMaterialPill {
            text: root.showDate ? root.formattedDate : ""
            // A file dragged over it lights the pill as hover does.
            hover: mouseArea.containsMouse || dropArea.containsDrag
            press: mouseArea.pressed

            // One weight up from the date: the key value of the pair.
            StyledText {
                anchors.centerIn: parent
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnPrimaryContainer
                text: root.formattedTime
            }
        }
    }

    RowLayout {
        id: rowLayout
        visible: !root.material
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

        ClockWidgetPopup {
            hoverTarget: mouseArea
        }
    }
}
