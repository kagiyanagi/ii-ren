pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One tool invocation, rendered the way the CLI narrates its own work:
 * a status dot, the tool name, and a one-line argument summary.
 * Clicking expands the raw result.
 */
Item {
    id: root

    required property var part

    property bool expanded: false

    implicitHeight: layout.implicitHeight
    implicitWidth: layout.implicitWidth

    ColumnLayout {
        id: layout
        width: root.width
        spacing: 2

        RippleButton {
            id: headerButton
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight + 10
            buttonRadius: Appearance.rounding.verysmall
            colBackground: "transparent"
            enabled: (root.part?.toolResult ?? "").length > 0
            onClicked: root.expanded = !root.expanded

            RowLayout {
                id: headerRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                MaterialSymbol { // Status
                    text: {
                        if (root.part?.toolFailed) return "error";
                        if (root.part?.toolRunning) return "pending";
                        return "check_circle";
                    }
                    iconSize: Appearance.font.pixelSize.normal
                    color: {
                        if (root.part?.toolFailed) return Appearance.colors.colError;
                        if (root.part?.toolRunning) return Appearance.colors.colSubtext;
                        return Appearance.colors.colPrimary;
                    }
                }

                StyledText { // Tool name
                    text: root.part?.toolName ?? ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }

                StyledText { // Argument summary
                    Layout.fillWidth: true
                    text: root.part?.toolInput ?? ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideMiddle
                }

                MaterialSymbol {
                    visible: headerButton.enabled
                    text: root.expanded ? "expand_less" : "expand_more"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
            }
        }

        Rectangle { // Raw result
            Layout.fillWidth: true
            visible: root.expanded && (root.part?.toolResult ?? "").length > 0
            implicitHeight: visible ? resultText.implicitHeight + 16 : 0
            radius: Appearance.rounding.verysmall
            color: Appearance.colors.colLayer2

            StyledText {
                id: resultText
                anchors.fill: parent
                anchors.margins: 8
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.monospace
                color: root.part?.toolFailed ? Appearance.colors.colError : Appearance.colors.colSubtext
                // Long outputs are truncated: this is an activity log, not a file viewer.
                text: {
                    const full = root.part?.toolResult ?? "";
                    return full.length > 4000 ? full.slice(0, 4000) + "\n\n… truncated" : full;
                }
            }
        }
    }
}
