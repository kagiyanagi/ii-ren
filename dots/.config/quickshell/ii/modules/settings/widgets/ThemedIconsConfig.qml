pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

Item {
    id: subPageRoot
    anchors.fill: parent

    // ConfigSubPageHost binds these on whatever the Loader produced, and that is
    // this Item -- so they stay here, and the nested ContentPage's own pair is
    // driven from them rather than from a hand-rolled header.
    property bool showBackButton: false
    signal goBack()

    readonly property bool hasIconPacks: IconThemes.availableThemes.length > 0
    readonly property bool canPreview: IconThemes.enableThemed && subPageRoot.hasIconPacks
    // Which of the two pickers is the one you are looking at right now. The
    // preview follows it, so changing the pack for the other mode is visibly a
    // change for later rather than a control that did nothing.
    readonly property bool darkMode: Appearance.m3colors.darkmode
    readonly property string effectiveThemeId: subPageRoot.darkMode ? IconThemes.darkTheme : IconThemes.lightTheme
    readonly property var effectiveTheme: IconThemes.availableThemes.find(theme => theme.id === subPageRoot.effectiveThemeId) ?? null

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        title: Translation.tr("Icon Packs (Apps & Folders)")
        showBackButton: subPageRoot.showBackButton
        onGoBack: subPageRoot.goBack()

        ContentSection {
            title: Translation.tr("Icon Packs")
            icon: "category"
            // This was a 40-line explanation card sitting above the options. It
            // is a scope note for the section, and a section already has a place
            // to put one.
            tooltip: Translation.tr("Select icon packs for apps and folders across KDE (Dolphin, Qt) and GTK. Packs marked with ✦ (like Breeze and Breeze Plus) natively adapt their folder colors to your wallpaper.")

            // The preview is the page, and it comes first: the pack that is in
            // force right now, and whether it recolours folders with the
            // wallpaper. Everything below only changes what this shows.
            Item {
                id: preview
                readonly property bool wantsCard: true
                readonly property bool dynamicPack: subPageRoot.effectiveTheme?.dynamic === true

                Layout.fillWidth: true
                visible: subPageRoot.canPreview
                implicitHeight: previewRow.implicitHeight + 32

                RowLayout {
                    id: previewRow
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    // A dynamic pack tints its folders with the wallpaper accent,
                    // so the preview folder carries that accent when the pack is
                    // one and a neutral when it is not -- the ✦ in the chip
                    // labels, shown rather than spelled. A plain symbol and not a
                    // MaterialShape tile: that is a Canvas that repaints on every
                    // colour frame, and this directory's effect budget is zero.
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "folder"
                        fill: 1
                        // 48: DESIGN.md 5.4's size for an app icon or tile, which
                        // is what an icon pack's folder is.
                        iconSize: 48
                        color: preview.dynamicPack ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: subPageRoot.effectiveTheme?.name ?? subPageRoot.effectiveThemeId
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.family: Appearance.font.family.title
                            color: Appearance.colors.colOnSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            // Names the mode this is previewing, and what the
                            // system reports back -- which is why the apply button
                            // below no longer needs a two-second "Applied!" flash.
                            text: {
                                const mode = subPageRoot.darkMode ? Translation.tr("Dark mode") : Translation.tr("Light mode");
                                if (IconThemes.currentSystemTheme.length === 0)
                                    return `${mode} · ${Translation.tr("detecting the live pack…")}`;
                                return `${mode} · ${Translation.tr("live: %1").arg(IconThemes.currentSystemTheme)}`;
                            }
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    Pill {
                        Layout.alignment: Qt.AlignVCenter
                        implicitHeight: 28
                        implicitWidth: dynamicBadgeText.implicitWidth + 16
                        color: preview.dynamicPack ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        StyledText {
                            id: dynamicBadgeText
                            anchors.centerIn: parent
                            text: preview.dynamicPack ? Translation.tr("Dynamic") : Translation.tr("Static")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: preview.dynamicPack ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }

            // Two edge states share the preview's slot, because in both of them
            // there is nothing to preview. The switch that turns management back
            // on stays below: it is on this page, so the placeholder cannot be the
            // only thing in the section the way it is elsewhere in this family.
            Item {
                Layout.fillWidth: true
                implicitHeight: Appearance.sizes.pagePlaceholderHeight
                visible: !subPageRoot.canPreview

                PagePlaceholder {
                    anchors.fill: parent
                    shape: MaterialShape.Shape.Circle
                    icon: IconThemes.enableThemed ? "folder_off" : "palette"
                    title: IconThemes.enableThemed ? Translation.tr("No icon packs found") : Translation.tr("Icon theming is off")
                    description: IconThemes.enableThemed
                        ? Translation.tr("Nothing in /usr/share/icons, ~/.local/share/icons or ~/.icons ships an icon theme. Install one and it shows up here.")
                        : Translation.tr("Turn on icon theme management to choose packs for light and dark mode.")
                }
            }

            ConfigSwitch {
                buttonIcon: "palette"
                text: Translation.tr("Enable icon theme management")
                checked: IconThemes.enableThemed
                onCheckedChanged: IconThemes.setThemed(checked)

                StyledToolTip {
                    text: Translation.tr("Synchronizes icon packs across KDE and GTK with light and dark mode switching.")
                }
            }

            // Dimmed and disabled rather than hidden: the option still exists, it
            // just does not apply while management is off.
            ConfigSwitch {
                enabled: IconThemes.enableThemed
                buttonIcon: "dark_mode"
                text: Translation.tr("Auto-switch between light and dark packs")
                checked: IconThemes.autoSwitchWithDarkMode
                onCheckedChanged: {
                    IconThemes.autoSwitchWithDarkMode = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Automatically toggles between your light and dark icon pack selections when night light or dark mode toggles.")
                }
            }

            ContentSubsection {
                visible: subPageRoot.canPreview
                title: Translation.tr("Light Mode Icon Pack")
                icon: "light_mode"
                Layout.fillWidth: true
                tooltip: Translation.tr("Icon pack applied during Light Mode. Marked with ✦ are dynamic packs that recolor folders with your wallpaper.")

                ConfigSelectionArray {
                    currentValue: IconThemes.lightTheme
                    onSelected: (newValue) => {
                        IconThemes.lightTheme = newValue;
                        // Picking for the mode you are in is applying, as it
                        // already is on the cursor page -- otherwise the control
                        // looks like it did nothing until you find Apply. Picking
                        // for the other mode is a change for later, and applying
                        // it would re-run the script over an unchanged pack.
                        if (!subPageRoot.darkMode)
                            IconThemes.applyCurrent();
                    }
                    options: IconThemes.availableThemes.map((theme) => {
                        return ({
                            "displayName": (theme.dynamic ? "✦ " : "") + theme.name,
                            "value": theme.id,
                            "icon": theme.dynamic ? "auto_awesome" : "folder"
                        });
                    })
                }
            }

            ContentSubsection {
                visible: subPageRoot.canPreview
                title: Translation.tr("Dark Mode Icon Pack")
                icon: "dark_mode"
                Layout.fillWidth: true
                tooltip: Translation.tr("Icon pack applied during Dark Mode. Marked with ✦ are dynamic packs that recolor folders with your wallpaper.")

                ConfigSelectionArray {
                    currentValue: IconThemes.darkTheme
                    onSelected: (newValue) => {
                        IconThemes.darkTheme = newValue;
                        if (subPageRoot.darkMode)
                            IconThemes.applyCurrent();
                    }
                    options: IconThemes.availableThemes.map((theme) => {
                        return ({
                            "displayName": (theme.dynamic ? "✦ " : "") + theme.name,
                            "value": theme.id,
                            "icon": theme.dynamic ? "auto_awesome" : "folder"
                        });
                    })
                }
            }

            // Picking already applies, so this is the "it did not take" escape
            // hatch, not the page's primary action. It is therefore shaped like a
            // settings row rather than a full-width accented button, and its
            // confirmation is the preview's live line, not a 2s label swap.
            RippleButtonWithIcon {
                Layout.fillWidth: true
                readonly property bool wantsCard: true
                enabled: IconThemes.enableThemed
                implicitHeight: contentItem.implicitHeight + 12 * 2
                buttonRadius: Appearance.rounding.verysmall
                materialIcon: "magic_button"
                mainText: Translation.tr("Re-apply to Dolphin & GTK")
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                onClicked: IconThemes.applyCurrent()
            }
        }
    }
}
