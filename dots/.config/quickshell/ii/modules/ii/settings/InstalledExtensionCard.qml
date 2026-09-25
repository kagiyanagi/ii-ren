import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "."

// One installed extension: an Android Settings app row with a trailing switch.
// The row expands into the extension's options and its actions.
Item {
    id: root
    required property var modelData
    required property int listCount
    required property int index

    readonly property var ext: modelData
    readonly property var updateState: ExtensionManager.updateStates[ext.id] ?? {}
    readonly property bool updateChecking: updateState.checking ?? false
    readonly property bool updateAvailable: (updateState.updateAvailable ?? false) && !updateChecking
    readonly property bool hasConfigSchema: Object.keys(ext.configSchema ?? {}).length > 0
    readonly property bool active: ext.enabled && Config.options.extensions.enable
    property bool expanded: false
    property bool confirmRemove: false
    // Expand on default spatial, collapse on the fast exit, as NotificationGroup does.
    property AnimSpec expandSpec: Appearance.animation.elementMove

    readonly property real topRadius: index === 0 ? Appearance.rounding.large : Appearance.rounding.verysmall
    readonly property real bottomRadius: index === listCount - 1 ? Appearance.rounding.large : Appearance.rounding.verysmall

    function toggleExpanded() {
        root.expandSpec = root.expanded ? Appearance.animation.elementMoveExit : Appearance.animation.elementMove
        root.expanded = !root.expanded
        root.confirmRemove = false
    }

    Layout.fillWidth: true
    implicitHeight: header.height + panel.height

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colSurfaceContainerHigh
        topLeftRadius: root.topRadius
        topRightRadius: root.topRadius
        bottomLeftRadius: root.bottomRadius
        bottomRightRadius: root.bottomRadius
    }

    RippleButton {
        id: header
        width: parent.width
        height: 72
        colBackground: "transparent"
        topLeftRadius: root.topRadius
        topRightRadius: root.topRadius
        bottomLeftRadius: panel.height > 0 ? 0 : root.bottomRadius
        bottomRightRadius: bottomLeftRadius
        onClicked: root.toggleExpanded()
        // Button answers Space only; a row that opens something takes Enter too.
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
    }

    RowLayout {
        anchors {
            left: header.left
            right: header.right
            verticalCenter: header.verticalCenter
            leftMargin: 16
            rightMargin: 16
        }
        spacing: 16

        MaterialShape {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            shapeString: root.ext.shapeString || ""
            color: root.active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.ext.icon || "extension"
                iconSize: 24
                color: root.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    text: root.ext.name
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
                    icon: "link"
                    tooltip: Translation.tr("Custom URL — installed from a custom link")
                    visible: root.ext.isCustomUrl ?? false
                }
                ExtensionBadge {
                    icon: "folder"
                    tooltip: Translation.tr("Local path extension — files linked from your filesystem")
                    visible: root.ext.isLocal ?? false
                }
                // Lets the row grow; without it the row's maximum is its content
                // and the column beside the shape could not take the free width.
                Item { Layout.fillWidth: true }
            }

            // Only the status that asks for something is shown; "up to date"
            // is the default and says nothing.
            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: [root.ext.version, root.ext.author].filter(Boolean).join(" · ")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    visible: root.updateAvailable
                    text: " · " + Translation.tr("Update available")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colPrimary
                }
                Item { Layout.fillWidth: true }
            }
        }

        StyledSwitch {
            enabled: Config.options.extensions.enable
            checked: root.ext.enabled
            onClicked: ExtensionManager.toggleExtension(root.ext.id, !root.ext.enabled)
        }

        MaterialSymbol {
            text: "expand_more"
            iconSize: 24
            color: Appearance.colors.colSubtext
            rotation: root.expanded ? 180 : 0
            Behavior on rotation {
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
            }
        }
    }

    Item {
        id: panel
        y: header.height
        width: parent.width
        height: root.expanded ? panelContent.implicitHeight : 0
        clip: true
        Behavior on height {
            NumberAnimation {
                duration: root.expandSpec.duration
                easing.type: root.expandSpec.type
                easing.bezierCurve: root.expandSpec.bezierCurve
            }
        }

        ColumnLayout {
            id: panelContent
            // A collapsed row still instantiates its buttons; hidden, they
            // cost no offscreen pass.
            visible: panel.height > 0
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                visible: text.length > 0
                text: root.ext.description || ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            ExtensionConfigPanel {
                Layout.fillWidth: true
                // The group's cards bleed 8 past their rows, so this lands them
                // 8 inside the extension card.
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                visible: root.hasConfigSchema
                extensionId: root.ext.id
                schema: root.ext.configSchema ?? {}
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.topMargin: 4
                Layout.bottomMargin: 16
                spacing: 8

                ActionButton {
                    visible: (root.ext.repoUrl?.length ?? 0) > 0 && !root.ext.isLocal
                    buttonText: root.updateChecking ? Translation.tr("Checking…")
                        : root.updateAvailable ? Translation.tr("Update") : Translation.tr("Check for updates")
                    tone: root.updateAvailable ? "primary" : "secondary"
                    onClicked: {
                        if (root.updateChecking) return
                        if (root.updateAvailable) ExtensionManager.updateExtension(root.ext.id)
                        else ExtensionManager.checkUpdate(root.ext.id)
                    }
                }
                ActionButton {
                    visible: root.ext.isLocal ?? false
                    buttonText: Translation.tr("Reload")
                    onClicked: ExtensionManager.reinstallLocalExtension(root.ext.id)
                }
                ActionButton {
                    visible: root.hasConfigSchema
                    buttonText: Translation.tr("Reset to defaults")
                    onClicked: ExtensionManager.resetExtensionConfig(root.ext.id)
                }
                ActionButton {
                    // Reading the repo needs nothing running, so this one
                    // stays live with extensions off.
                    enabled: true
                    visible: (root.ext.htmlUrl || root.ext.repoUrl || "").length > 0
                    buttonText: Translation.tr("Repository")
                    onClicked: Qt.openUrlExternally(root.ext.htmlUrl || root.ext.repoUrl)
                }
                Item { Layout.fillWidth: true }
                // Removing deletes the clone and the extension's settings, so
                // it asks twice, and it stands apart from the rest.
                ActionButton {
                    buttonText: root.confirmRemove ? Translation.tr("Confirm remove") : Translation.tr("Remove")
                    tone: "error"
                    onClicked: {
                        if (!root.confirmRemove) {
                            root.confirmRemove = true
                            disarmTimer.restart()
                            return
                        }
                        ExtensionManager.uninstallExtension(root.ext.id)
                    }
                }
            }
        }
    }

    Timer {
        id: disarmTimer
        interval: 4000
        onTriggered: root.confirmRemove = false
    }

    component ActionButton: DialogButton {
        property string tone: "secondary"
        enabled: Config.options.extensions.enable
        implicitHeight: 32
        colBackground: tone === "primary" ? Appearance.colors.colPrimaryContainer
            : tone === "error" ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
        colBackgroundHover: tone === "primary" ? Appearance.colors.colPrimaryContainerHover
            : tone === "error" ? Appearance.colors.colErrorContainerHover : Appearance.colors.colSecondaryContainerHover
        colRipple: tone === "primary" ? Appearance.colors.colPrimaryContainerActive
            : tone === "error" ? Appearance.colors.colErrorContainerActive : Appearance.colors.colSecondaryContainerActive
        colEnabled: tone === "primary" ? Appearance.colors.colOnPrimaryContainer
            : tone === "error" ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
        // The 0.4 opacity is the disabled state; DialogButton's outline
        // text on top of it dimmed these twice.
        colDisabled: colEnabled
    }
}
