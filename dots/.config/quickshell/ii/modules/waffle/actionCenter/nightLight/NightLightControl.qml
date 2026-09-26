pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.actionCenter

Item {
    id: root

    WPanelPageColumn {
        anchors.fill: parent

        BodyRectangle {
            implicitHeight: 400
            implicitWidth: 50

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 4

                HeaderRow {
                    Layout.fillWidth: true
                    title: Translation.tr("Eye protection")
                }

                ToggleItem {
                    Layout.fillWidth: true
                    name: Translation.tr("Automatic")
                    description: Translation.tr("Automatically turns on at night")
                    iconName: "clock"
                    checked: Config.options.nightLight.auto
                    onCheckedChanged: Config.options.nightLight.auto = checked
                }

                ToggleItem {
                    Layout.fillWidth: true
                    name: Translation.tr("Night Light")
                    description: Translation.tr("Hyprsunset warm screen filter")
                    iconName: "weather-sunny"
                    checked: Hyprsunset.active
                    onCheckedChanged: Hyprsunset.active = checked
                }

                ToggleItem {
                    Layout.fillWidth: true
                    name: Translation.tr("Reading mode")
                    description: Translation.tr("Hyprland monochrome screen filter")
                    iconName: "book-open"
                    checked: HyprlandReadingMode.active
                    onCheckedChanged: HyprlandReadingMode.active = checked
                }

                ToggleItem {
                    Layout.fillWidth: true
                    name: Translation.tr("Anti-flashbang")
                    description: Translation.tr("Hyprland shader to invert white screens")
                    iconName: "lightbulb-filament"
                    checked: HyprlandAntiFlashbangShader.active
                    onCheckedChanged: HyprlandAntiFlashbangShader.active = checked
                }

                Item {
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                }
            }
        }
    }
}
