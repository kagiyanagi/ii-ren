pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true

    // Lifted and run under node by tools/check-about.py.
    function cpuName(model) {
        if (!model || model === "--") return Translation.tr("Unknown")
        return model.replace(/\((R|TM)\)/gi, "").replace(/\s*@.*$/, "").replace(/\s+(CPU|\d+-Core Processor)\b/gi, "").replace(/\s+/g, " ").trim()
    }
    function gpuName(model) {
        if (!model || model === "--") return Translation.tr("Unknown")
        const m = model.replace(/\s*\(rev \w+\)/i, "")
        const vendor = /nvidia/i.test(m) ? "NVIDIA" : /intel/i.test(m) ? "Intel" : /advanced micro|amd|\bati\b/i.test(m) ? "AMD" : ""
        const brackets = (m.match(/\[[^\]]+\]/g) ?? []).map(b => b.slice(1, -1)).filter(b => b !== "AMD/ATI")
        const name = (brackets.length ? brackets[brackets.length - 1] : m.replace(/^.*?(Corporation|Inc\.)\s*(\[AMD\/ATI\])?\s*/i, "")).trim()
        return name.toLowerCase().startsWith(vendor.toLowerCase()) ? name : `${vendor} ${name}`.trim()
    }
    function bytes(n) {
        const gb = n / 1024 ** 3
        if (gb >= 1000) return `${(gb / 1024).toFixed(1)} TB`
        return `${gb.toFixed(gb >= 100 ? 0 : 1)} GB`
    }

    // Read once: none of these change while the page is open.
    FileView { id: hostnameFile; path: "/proc/sys/kernel/hostname"; blockLoading: true }
    FileView { id: kernelFile; path: "/proc/sys/kernel/osrelease"; blockLoading: true }
    FileView { id: cpuinfoFile; path: "/proc/cpuinfo"; blockLoading: true }
    readonly property int threads: (cpuinfoFile.text().match(/^processor\s*:/gm) ?? []).length

    EasterEggWindow {
        id: easterEggWindow
    }

    // One card per project: logo, name, byline, repo link, then its link chips.
    // A ContentGroup row (wantsCard), so a run of them reads as one grouped list.
    component Project: Item {
        id: project
        readonly property bool wantsCard: true
        property string name
        property int nameSize: Appearance.font.pixelSize.title
        property string byline
        property string detail
        property string url
        property int logoSize: 80
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
                    implicitWidth: project.logoSize
                    implicitHeight: project.logoSize
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: project.name
                        font.pixelSize: project.nameSize
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: project.byline !== ""
                        text: project.byline
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: project.detail !== ""
                        text: project.detail
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

    // The machine itself, the way About phone opens on the device.
    ContentGroup {
        Project {
            name: hostnameFile.text().trim() || SystemInfo.username
            nameSize: Appearance.font.pixelSize.hugeass
            logoSize: 96
            byline: SystemInfo.distroName
            detail: [`Linux ${kernelFile.text().trim()}`, Translation.tr("Up %1").arg(DateTime.uptime)].join("  ·  ")
            links: [
                ["language", Translation.tr("Website"), SystemInfo.homeUrl],
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

    ContentSection {
        icon: "memory"
        title: Translation.tr("Hardware")

        // The tiles paint their own cards, so they bleed as ContentGroup's do
        // and meet the same edges as the cards above and below.
        Item {
            Layout.fillWidth: true
            implicitHeight: specs.implicitHeight

            GridLayout {
                id: specs
                x: -8
                width: parent.width + 16
                columns: 2
                rowSpacing: 4
                columnSpacing: 4
                uniformCellWidths: true

                SpecTile {
                    corner: 0
                    icon: "memory"
                    label: Translation.tr("Processor")
                    value: page.cpuName(ResourceUsage.cpuModel)
                    detail: [page.threads > 0 ? Translation.tr("%1 threads").arg(page.threads) : "",
                        ResourceUsage.maxAvailableCpuString !== "--" ? Translation.tr("up to %1").arg(ResourceUsage.maxAvailableCpuString) : ""]
                        .filter(s => s).join("  ·  ")
                }
                SpecTile {
                    corner: 1
                    icon: "developer_board"
                    label: Translation.tr("Graphics")
                    value: page.gpuName(ResourceUsage.gpuModel)
                    // Physical pixels: a screen's width is logical under fractional scaling.
                    detail: Quickshell.screens.map(s => `${Math.round(s.width * s.devicePixelRatio)} × ${Math.round(s.height * s.devicePixelRatio)}`).join(", ")
                }
                SpecTile {
                    corner: 2
                    icon: "memory_alt"
                    label: Translation.tr("Memory")
                    value: page.bytes(ResourceUsage.memoryTotal * 1024)
                    usage: ResourceUsage.memoryUsedPercentage
                    detail: Translation.tr("%1 in use").arg(page.bytes(ResourceUsage.memoryUsed * 1024))
                }
                SpecTile {
                    corner: 3
                    icon: "hard_drive"
                    label: Translation.tr("Storage")
                    value: page.bytes(ResourceUsage.diskTotal)
                    usage: ResourceUsage.diskUsedPercentage
                    detail: Translation.tr("%1 used on %2").arg(page.bytes(ResourceUsage.diskUsed)).arg(Config.options?.resources?.diskMount ?? "/")
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
}
