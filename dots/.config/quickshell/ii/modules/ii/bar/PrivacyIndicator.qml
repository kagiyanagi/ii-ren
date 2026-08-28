import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import "./cards"

MouseArea {
    id: indicator
    property bool vertical: false
    property color colText: Appearance.colors.colOnPrimary

    readonly property var entries: PrivacyMonitor.entries

    hoverEnabled: true
    implicitWidth: vertical ? 20 : contentLayout.implicitWidth + 12
    implicitHeight: vertical ? contentLayout.implicitHeight + 12 : 20

    Component.onCompleted: {
        rootItem.toggleHighlight(true);
        indicator.updateVisibility();
    }
    onEntriesChanged: indicator.updateVisibility()

    function updateVisibility() {
        rootItem.toggleVisible(indicator.entries.length > 0);
    }

    function iconFor(kind) {
        return kind === "microphone" ? "mic" : "location_on";
    }

    function labelFor(kind) {
        return kind === "microphone" ? Translation.tr("Microphone") : Translation.tr("Location");
    }

    GridLayout {
        id: contentLayout
        anchors.centerIn: parent
        flow: indicator.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: indicator.vertical ? indicator.entries.length : 1
        columns: indicator.vertical ? 1 : indicator.entries.length
        rowSpacing: 2
        columnSpacing: 2

        Repeater {
            model: indicator.entries
            delegate: MaterialSymbol {
                required property var modelData
                text: indicator.iconFor(modelData.kind)
                fill: 1
                color: indicator.colText
                iconSize: Appearance.font.pixelSize.larger
            }
        }
    }

    StyledPopup {
        hoverTarget: indicator
        contentItem: ColumnLayout {
            anchors.centerIn: parent
            spacing: 8

            Repeater {
                model: indicator.entries
                delegate: SectionCard {
                    required property var modelData
                    icon: indicator.iconFor(modelData.kind)
                    title: indicator.labelFor(modelData.kind)
                    headerExtraText: Translation.tr("In use")
                    // GeoClue only tells a client its own name, so an app that
                    // talks to it over raw D-Bus stays anonymous.
                    subtitle: modelData.apps.length > 0 ? "" : Translation.tr("An unidentified app is using your location")
                    showDivider: modelData.apps.length > 0
                    spacing: 6

                    Repeater {
                        model: modelData.apps
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8

                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: modelData.name
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                visible: modelData.pid > 0
                                text: `${modelData.process} · ${modelData.pid}`
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                }
            }
        }
    }
}
