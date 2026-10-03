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

    readonly property bool hasCursorPacks: CursorTheme.availableThemes.length > 0
    // The size range the page offers, named once: the spin box takes it as its
    // bounds, and the preview reserves the widest of it so the lines beside the
    // pointer hold still while the pointer grows.
    readonly property int minCursorSize: 12
    readonly property int maxCursorSize: 96

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        title: Translation.tr("Cursor configuration")
        showBackButton: subPageRoot.showBackButton
        onGoBack: subPageRoot.goBack()

        ContentSection {
            title: Translation.tr("Cursor & pointer")
            icon: "arrow_selector_tool"
            // This was a 40-line explanation card sitting above the options. It
            // is a scope note for the section, and a section already has a place
            // to put one.
            tooltip: Translation.tr("Configures the cursor theme and size across Hyprland, GTK apps, and Qt/KDE. Changes apply immediately without restarting your compositor.")

            // The preview is the page, and it comes first: the pointer at the
            // size it will really be, beside the theme that is live right now.
            // Everything below only changes what this shows.
            Item {
                id: preview
                readonly property bool wantsCard: true

                Layout.fillWidth: true
                visible: subPageRoot.hasCursorPacks
                implicitHeight: previewRow.implicitHeight + 32

                RowLayout {
                    id: previewRow
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    // A fixed cell for a glyph that ranges over 12..96px, so the
                    // text beside it does not reflow every time the size changes.
                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: subPageRoot.maxCursorSize
                        implicitHeight: pointerGlyph.implicitHeight

                        MaterialSymbol {
                            id: pointerGlyph
                            anchors.centerIn: parent
                            text: "arrow_selector_tool"
                            // 1:1 with what the compositor will draw. Deliberately
                            // not tweened: iconSize also feeds the symbol's `opsz`
                            // axis, so animating it remaps a variable font every
                            // frame, and this directory's effect budget is zero.
                            iconSize: CursorTheme.configuredSize
                            fill: 1
                            color: Appearance.colors.colPrimary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: CursorTheme.currentThemeDetails?.name ?? CursorTheme.configuredTheme
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.family: Appearance.font.family.title
                            color: Appearance.colors.colOnSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            // The one line that says whether the system actually
                            // took the selection -- which is why the apply button
                            // below no longer needs a two-second "Applied!" flash.
                            text: {
                                if (!CursorTheme.currentSystemTheme)
                                    return Translation.tr("Detecting the live pointer…");
                                const live = Translation.tr("Live: %1 · %2px").arg(CursorTheme.currentSystemTheme).arg(CursorTheme.currentSystemSize);
                                const sizes = CursorTheme.currentThemeDetails?.sizes ?? [];
                                if (sizes.length === 0)
                                    return live;
                                return `${live} · ${Translation.tr("ships %1px").arg(sizes.join(", "))}`;
                            }
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }

            // Nothing to pick from. The text field further down is the way out,
            // so the placeholder names it rather than leaving a dead end.
            Item {
                Layout.fillWidth: true
                implicitHeight: Appearance.sizes.pagePlaceholderHeight
                visible: !subPageRoot.hasCursorPacks

                PagePlaceholder {
                    anchors.fill: parent
                    icon: "mouse"
                    shape: MaterialShape.Shape.Circle
                    title: Translation.tr("No cursor packs found")
                    description: Translation.tr("Nothing in ~/.icons, ~/.local/share/icons or /usr/share/icons ships a cursor theme. Install one, or type its name under Custom Cursor Theme Name below.")
                }
            }

            // Theme Selection -- the primary control, first under the header.
            ContentSubsection {
                visible: subPageRoot.hasCursorPacks
                title: Translation.tr("Installed cursor packs")
                icon: "category"
                Layout.fillWidth: true
                tooltip: Translation.tr("Select a cursor theme detected from ~/.icons, ~/.local/share/icons, or /usr/share/icons")

                ConfigSelectionArray {
                    currentValue: CursorTheme.configuredTheme
                    onSelected: (newValue) => {
                        CursorTheme.setCursor(newValue, CursorTheme.configuredSize);
                    }
                    options: CursorTheme.availableThemes.map((theme) => {
                        return ({
                            "displayName": theme.name,
                            "value": theme.id,
                            "icon": "arrow_selector_tool"
                        });
                    })
                }
            }

            // Size: the presets, the exact value and the warning about it are one
            // option, so they share one card run instead of three loose blocks.
            ContentSubsection {
                title: Translation.tr("Cursor size")
                icon: "format_size"
                Layout.fillWidth: true
                tooltip: Translation.tr("Select a standard cursor size or use the spin box for custom sizes")

                ConfigSelectionArray {
                    currentValue: CursorTheme.configuredSize
                    onSelected: (newValue) => {
                        CursorTheme.setCursor(CursorTheme.configuredTheme, newValue);
                    }
                    options: [
                        { "displayName": "16 px", "value": 16, "icon": "mouse" },
                        { "displayName": "20 px", "value": 20, "icon": "mouse" },
                        { "displayName": "24 px", "value": 24, "icon": "mouse" },
                        { "displayName": "28 px", "value": 28, "icon": "mouse" },
                        { "displayName": "32 px", "value": 32, "icon": "mouse" },
                        { "displayName": "36 px", "value": 36, "icon": "mouse" },
                        { "displayName": "48 px", "value": 48, "icon": "mouse" }
                    ]
                }

                ConfigSpinBox {
                    icon: "photo_size_select_small"
                    text: Translation.tr("Custom size (px)")
                    from: subPageRoot.minCursorSize
                    to: subPageRoot.maxCursorSize
                    stepSize: 2
                    value: CursorTheme.configuredSize
                    onValueChanged: {
                        if (value !== CursorTheme.configuredSize) {
                            CursorTheme.setCursor(CursorTheme.configuredTheme, value);
                        }
                    }
                }

                // Warning if chosen size is below theme's minimum available bitmap
                NoticeBox {
                    Layout.fillWidth: true
                    visible: Boolean(CursorTheme.currentThemeDetails?.min_size && (CursorTheme.configuredSize < CursorTheme.currentThemeDetails.min_size))
                    materialIcon: "warning"
                    text: Translation.tr("The selected theme (%1) only includes bitmaps down to %2px. Hyprland and GTK will display %2px instead of %3px. Switch to a theme with smaller bitmaps (such as macOS-White or Breeze) to use %3px.")
                        .arg(CursorTheme.configuredTheme)
                        .arg(CursorTheme.currentThemeDetails?.min_size ?? 24)
                        .arg(CursorTheme.configuredSize)
                }
            }

            ConfigSwitch {
                buttonIcon: "my_location"
                text: Translation.tr("Shake to find the pointer")
                checked: Config.options.interactions.shakeToFind.enable
                onCheckedChanged: {
                    Config.options.interactions.shakeToFind.enable = checked;
                }

                StyledToolTip {
                    text: Translation.tr("Wiggle the mouse and a ring closes in on the pointer, so it is easy to spot on a large screen.")
                }
            }

            // Custom Theme Name Override -- also the only way out of the empty
            // state, which is why it stays visible when nothing was detected.
            ContentSubsection {
                title: Translation.tr("Custom cursor theme name")
                icon: "edit"
                Layout.fillWidth: true
                tooltip: Translation.tr("Manually enter a cursor theme name if you have a custom pack installed")

                // Not ConfigTextField: it publishes `inputText` on every
                // keystroke and exposes no commit signal, and each keystroke here
                // would execDetached the apply script. MaterialTextField is the
                // same shared input with an editingFinished to hang that on.
                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("e.g., bibata-modern-classic")
                    text: CursorTheme.configuredTheme
                    onEditingFinished: {
                        if (text.trim().length > 0) {
                            CursorTheme.setCursor(text.trim(), CursorTheme.configuredSize);
                        }
                    }
                }
            }

            // Every control above already applies on change -- CursorTheme.setCursor
            // runs the script itself -- so this is the "it did not take" escape
            // hatch, not the page's primary action. It is therefore shaped like a
            // settings row rather than a full-width accented button, and its
            // confirmation is the preview's live line, not a 2s label swap.
            RippleButtonWithIcon {
                Layout.fillWidth: true
                readonly property bool wantsCard: true
                implicitHeight: contentItem.implicitHeight + 12 * 2
                buttonRadius: Appearance.rounding.verysmall
                materialIcon: "magic_button"
                mainText: Translation.tr("Re-apply to Hyprland, GTK & Qt")
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                onClicked: CursorTheme.applyCurrent()
            }
        }
    }
}
