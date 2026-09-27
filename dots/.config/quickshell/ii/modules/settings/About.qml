pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    EasterEggWindow {
        id: easterEggWindow
    }

    // One card per project: logo, name, byline, repo link, then its link chips.
    // A ContentGroup row (wantsCard), so a run of them reads as one grouped list.
    component Project: Item {
        id: project
        readonly property bool wantsCard: true
        property string name
        property string byline
        property string url
        // [icon, label, url, filled]. os-release fields are optional, so a link
        // with no url is dropped rather than drawn as a chip that opens nothing.
        property var links: []
        readonly property var shownLinks: links.filter(link => link[2])
        default property alias logo: logoSlot.data

        Layout.fillWidth: true
        implicitWidth: body.implicitWidth + 16
        implicitHeight: body.implicitHeight + 32

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            // ContentGroup bleeds the card 8 past the row; 8 more matches the 16 above.
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Item {
                    id: logoSlot
                    implicitWidth: 80
                    implicitHeight: 80
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: project.name
                        font.pixelSize: Appearance.font.pixelSize.title
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: project.byline !== ""
                        text: project.byline
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        visible: project.url !== ""
                        text: project.url
                        font.pixelSize: Appearance.font.pixelSize.normal
                        textFormat: Text.MarkdownText
                        onLinkActivated: link => Qt.openUrlExternally(link)
                        PointingHandLinkHover {}
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                visible: project.shownLinks.length > 0
                spacing: 4

                Repeater {
                    model: project.shownLinks

                    RippleButtonWithIcon {
                        required property var modelData
                        materialIcon: modelData[0]
                        mainText: modelData[1]
                        materialIconFill: modelData[3] ?? true
                        colBackground: Appearance.colors.colSurfaceContainerHighest
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: Appearance.colors.colSurfaceContainerHighestActive
                        onClicked: Qt.openUrlExternally(modelData[2])
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "folder_data"
        title: Translation.tr("This shell")

        Project {
            name: "ii-ren"
            byline: Translation.tr("A fork of ii-vynx")
            url: "https://github.com/kagiyanagi/ii-ren"
            links: [["adjust", Translation.tr("Issues"), "https://github.com/kagiyanagi/ii-ren/issues", false]]

            // Android's version easter egg: tap it three times.
            RippleButton {
                id: egg
                property int clickCount: 0
                anchors.fill: parent
                padding: 0
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colRipple: Appearance.colors.colPrimaryContainerActive
                onClicked: {
                    egg.clickCount++
                    eggClickTimer.restart()
                    if (egg.clickCount < 3) return
                    egg.clickCount = 0
                    easterEggWindow.show()
                }
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "android"
                    iconSize: 48
                    fill: 1
                    color: Appearance.colors.colOnPrimaryContainer
                }

                Timer {
                    id: eggClickTimer
                    interval: 500
                    onTriggered: egg.clickCount = 0
                }
            }
        }
    }

    ContentSection {
        icon: "account_tree"
        title: Translation.tr("Built on")

        Project {
            name: "ii-vynx"
            byline: Translation.tr("By vaguesyntax")
            url: "https://github.com/vaguesyntax/ii-vynx"
            links: [
                ["auto_stories", Translation.tr("Documentation"), "https://github.com/vaguesyntax/ii-vynx/wiki"],
                ["bug_report", Translation.tr("Known Issues"), "https://github.com/vaguesyntax/ii-vynx/wiki/Known-Issues-and-Limitations"],
                ["adjust", Translation.tr("Issues"), "https://github.com/vaguesyntax/ii-vynx/issues", false]
            ]

            CustomIcon {
                anchors.fill: parent
                source: "ii-vynx"
            }
        }
        Project {
            name: "illogical-impulse"
            byline: Translation.tr("By end-4")
            url: "https://github.com/end-4/dots-hyprland"
            links: [
                ["auto_stories", Translation.tr("Documentation"), "https://end-4.github.io/dots-hyprland-wiki/en/ii-qs/02usage/"],
                ["adjust", Translation.tr("Issues"), "https://github.com/end-4/dots-hyprland/issues", false],
                ["forum", Translation.tr("Discussions"), "https://github.com/end-4/dots-hyprland/discussions"],
                ["favorite", Translation.tr("Donate"), "https://github.com/sponsors/end-4"]
            ]

            IconImage {
                anchors.fill: parent
                source: Quickshell.iconPath("illogical-impulse")
            }
        }
    }

    ContentSection {
        icon: "box"
        title: Translation.tr("System")

        Project {
            name: SystemInfo.distroName
            url: SystemInfo.homeUrl
            links: [
                ["auto_stories", Translation.tr("Documentation"), SystemInfo.documentationUrl],
                ["support", Translation.tr("Help & Support"), SystemInfo.supportUrl],
                ["bug_report", Translation.tr("Report a Bug"), SystemInfo.bugReportUrl],
                ["policy", Translation.tr("Privacy Policy"), SystemInfo.privacyPolicyUrl, false]
            ]

            IconImage {
                anchors.fill: parent
                source: Quickshell.iconPath(SystemInfo.logo)
            }
        }
    }
}
