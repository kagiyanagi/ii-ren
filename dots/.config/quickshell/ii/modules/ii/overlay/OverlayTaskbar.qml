pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas

Rectangle {
    id: root

    property real padding: 8

    // One spec for the whole surface. No Behavior of its own: there is nothing here
    // that should leave on a different curve from the scrim it sits on.
    opacity: OverlayContext.shownProgress
    implicitWidth: contentRow.implicitWidth + (padding * 2)
    implicitHeight: contentRow.implicitHeight + (padding * 2)
    color: Appearance.m3colors.m3surfaceContainer
    radius: Appearance.rounding.large
    border.color: Appearance.colors.colOutlineVariant
    border.width: 1

    RowLayout {
        id: contentRow
        anchors {
            fill: parent
            margins: root.padding
        }
        // Whitespace on the 4dp grid where two 1px dividers used to be (11). The clock
        // and the battery are the second section; the widget toggles are the first.
        spacing: 12

        Row {
            spacing: 4
            Repeater {
                model: ScriptModel {
                    values: OverlayContext.availableWidgets
                }
                delegate: WidgetButton {
                    required property var modelData
                    identifier: modelData.identifier
                    materialSymbol: modelData.materialSymbol
                    title: modelData.title ?? OverlayContext.titleFor(modelData.identifier)
                }
            }
            Repeater {
                model: ScriptModel {
                    values: OverlayContext.extensionWidgets
                }
                delegate: WidgetButton {
                    required property var modelData
                    identifier: modelData.identifier
                    materialSymbol: modelData.materialSymbol
                    title: modelData.title ?? OverlayContext.titleFor(modelData.identifier)
                }
            }
        }

        TimeWidget {}
        BatteryWidget {
            visible: Battery.available
        }
    }

    component TimeWidget: StyledText {
        Layout.alignment: Qt.AlignVCenter

        text: DateTime.time
        color: Appearance.colors.colOnSurface
        font {
            family: Appearance.font.family.numbers
            variableAxes: Appearance.font.variableAxes.numbers
            pixelSize: Appearance.font.pixelSize.huge
        }
    }

    component BatteryWidget: Row {
        id: batteryWidget
        Layout.alignment: Qt.AlignVCenter
        spacing: 2
        property color colText: Battery.isLowAndNotCharging ? Appearance.colors.colError : Appearance.colors.colOnSurface

        MaterialSymbol {
            id: boltIcon
            anchors.verticalCenter: parent.verticalCenter
            fill: 1
            text: Battery.isCharging ? "bolt" : "battery_android_full"
            color: batteryWidget.colText
            iconSize: 24
            animateChange: true
        }
        
        StyledText {
            id: batteryText
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(Battery.percentage * 100) + "%"
            color: batteryWidget.colText
            font {
                family: Appearance.font.family.numbers
                variableAxes: Appearance.font.variableAxes.numbers
                pixelSize: Appearance.font.pixelSize.larger
            }
        }
    }

    component WidgetButton: RippleButton {
        id: widgetButton
        required property string identifier
        required property string materialSymbol
        required property string title

        Layout.alignment: Qt.AlignVCenter

        toggled: Persistent.states.overlay.open.includes(identifier)
        altAction: () => OverlayContext.requestCenter(identifier)
        onClicked: {
            if (widgetButton.toggled) {
                Persistent.states.overlay.open = Persistent.states.overlay.open.filter(type => type !== identifier);
            } else {
                Persistent.states.overlay.open.push(identifier);
            }
        }
        implicitWidth: implicitHeight

        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRippleToggled: Appearance.colors.colSecondaryContainerActive

        buttonRadius: root.radius - (root.height - height) / 2

        contentItem: Item {
            anchors.centerIn: parent
            implicitWidth: 32
            implicitHeight: 32
            MaterialSymbol {
                id: iconWidget
                anchors.centerIn: parent
                iconSize: 24
                text: widgetButton.materialSymbol
                color: widgetButton.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
            }
        }

        // Nine icons and no labels anywhere: `point_scan` and `browse_activity` are not
        // readable as a crosshair and a resource monitor. Same tooltip the card's own
        // title-bar buttons already carry.
        StyledToolTip {
            text: widgetButton.title
        }
    }
}
