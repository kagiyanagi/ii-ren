import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "."

// One search result, as a store list item: the row opens the repo page, the
// trailing button installs. Installed repos are filtered out upstream, so
// nothing here asks whether this one is installed.
Item {
    id: root
    required property var modelData
    required property int index
    required property int listCount

    readonly property var ext: modelData
    readonly property bool noJson: (ext.extensionJsonError ?? null) !== null
    readonly property bool recommended: ExtensionAudit.isExtensionRecommended(ext.name)
    readonly property string _auditState: {
        ExtensionAudit.auditDbVersion
        if (!ExtensionAudit.auditDatabaseReady || !ext.hasExtensionJson) return ""
        return ExtensionAudit.getExtensionAuditState(ext.name)
    }

    readonly property real topRadius: index === 0 ? Appearance.rounding.large : Appearance.rounding.verysmall
    readonly property real bottomRadius: index === listCount - 1 ? Appearance.rounding.large : Appearance.rounding.verysmall

    Layout.fillWidth: true
    implicitHeight: Math.max(row.implicitHeight + 24, 72)

    RippleButton {
        anchors.fill: parent
        colBackground: Appearance.colors.colSurfaceContainerHigh
        topLeftRadius: root.topRadius
        topRightRadius: root.topRadius
        bottomLeftRadius: root.bottomRadius
        bottomRightRadius: root.bottomRadius
        onClicked: Qt.openUrlExternally(root.ext.htmlUrl)
        // Button answers Space only; a row that opens something takes Enter too.
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
    }

    RowLayout {
        id: row
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 16
            rightMargin: 16
        }
        spacing: 16

        MaterialShape {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            shapeString: root.ext.shapeString || ""
            color: root.recommended ? Appearance.colors.colTertiary : Appearance.colors.colSurfaceContainerHighest

            HoverHandler {
                id: shapeHover
            }

            StyledToolTip {
                extraVisibleCondition: shapeHover.hovered && root.recommended
                text: Translation.tr("Recommended by the ii-vynx developer based on user feedback")
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.ext.icon || "extension"
                iconSize: 24
                color: root.recommended ? Appearance.colors.colOnTertiary : Appearance.colors.colOnSurfaceVariant
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: root.ext.displayName || root.ext.name
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }
                ExtensionBadge {
                    label: Translation.tr("Official")
                    tooltip: Translation.tr("Created by the ii-vynx developer")
                    visible: root.ext.repoUrl?.includes("vaguesyntax") ?? false
                }
                ExtensionBadge {
                    icon: root._auditState === "trusted" ? "verified" : "help"
                    bgColor: root._auditState === "trusted" ? Appearance.m3colors.m3successContainer : Appearance.colors.colErrorContainer
                    fgColor: root._auditState === "trusted" ? Appearance.m3colors.m3success : Appearance.colors.colError
                    tooltip: root._auditState === "trusted" ? Translation.tr("This extension is trusted. You can safely use it") : Translation.tr("This extension has not been audited yet. It may have security vulnerabilities.")
                    visible: root._auditState.length > 0 && root._auditState !== "blocked"
                }
                // Lets the row grow; without it the row's maximum is its content
                // and the column beside the shape could not take the free width.
                Item { Layout.fillWidth: true }
            }

            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.ext.description || ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                maximumLineCount: 2
            }

            StyledText {
                Layout.fillWidth: true
                text: root.noJson ? Translation.tr("No extension.json")
                    : ["★ " + root.ext.stars, root.ext.version].filter(Boolean).join(" · ")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.noJson ? Appearance.colors.colError : Appearance.colors.colSubtext
            }
        }

        DialogButton {
            // A repo without an extension.json clones and then fails to
            // register, leaving the clone behind.
            enabled: Config.options.extensions.enable && root.ext.hasExtensionJson
            buttonText: Translation.tr("Install")
            colBackground: Appearance.colors.colPrimaryContainer
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colRipple: Appearance.colors.colPrimaryContainerActive
            colEnabled: Appearance.colors.colOnPrimaryContainer
            // The 0.4 opacity is the disabled state; DialogButton's outline
            // text on top of it dimmed these twice.
            colDisabled: colEnabled
            StyledToolTip {
                extraVisibleCondition: root._auditState !== "trusted"
                text: Translation.tr("This extension has not been audited yet. It may have security vulnerabilities.")
            }
            onClicked: ExtensionManager.installExtension(root.ext.repoUrl, root.ext.name, root.ext.defaultBranch || "main", root.ext.htmlUrl)
        }
    }
}
