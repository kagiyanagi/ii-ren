import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.dock
import QtQuick
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: root
    spacing: 2

    DockMenuButton {
        Layout.fillWidth: true
        implicitHeight: 52
        symbolSize: 20
        sidePadding: 16
        contentSpacing: 16
        fontSize: Appearance.font.pixelSize.normal
        buttonRadius: 8
        colBackground: Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.08)
        colRipple: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.1)
        topLeftRadius: 23 // menuCard.outerRadius
        topRightRadius: 23
        symbolName: "flip_to_front"
        labelText: Translation.tr("Move to upper layer")
        onTriggered: {
            menuWindow.dismiss();
            let cloned = JSON.parse(JSON.stringify(Config.options.background.activeWidgets || []));
            const index = cloned.findIndex(w => w.id === GlobalStates.desktopMenuWidgetId);
            if (index >= 0) {
                const item = cloned.splice(index, 1)[0];
                cloned.push(item);
                Config.options.background.activeWidgets = cloned;
            }
        }
    }

    DockMenuButton {
        Layout.fillWidth: true
        implicitHeight: 52
        symbolSize: 20
        sidePadding: 16
        contentSpacing: 16
        fontSize: Appearance.font.pixelSize.normal
        buttonRadius: 8
        colBackground: Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.08)
        colRipple: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.1)
        symbolName: "settings"
        labelText: Translation.tr("Config")
        onTriggered: {
            menuWindow.dismiss();
            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("settings.qml")]);
        }
    }

    DockMenuButton {
        Layout.fillWidth: true
        implicitHeight: 52
        symbolSize: 20
        sidePadding: 16
        contentSpacing: 16
        fontSize: Appearance.font.pixelSize.normal
        buttonRadius: 8
        colBackground: Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.08)
        colRipple: ColorUtils.mix(Appearance.m3colors.m3onSurface, Appearance.colors.colSurfaceContainerHigh, 0.1)
        bottomLeftRadius: 23
        bottomRightRadius: 23
        symbolName: "delete"
        labelText: Translation.tr("Remove")
        onTriggered: {
            menuWindow.dismiss();
            let cloned = JSON.parse(JSON.stringify(Config.options.background.activeWidgets || []));
            cloned = cloned.filter(w => w.id !== GlobalStates.desktopMenuWidgetId);
            Config.options.background.activeWidgets = cloned;
        }
    }
}
