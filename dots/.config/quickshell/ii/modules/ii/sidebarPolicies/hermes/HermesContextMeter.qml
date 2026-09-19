pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Composer status pill: how full the context window is, and a tap-through to
 * a breakdown of what is in it plus the one action that helps -- folding the
 * conversation down.
 *
 * The breakdown popover reparents itself into the sidebar window's own
 * content item instead of staying in this component's tree: `inputWrapper` in
 * Hermes.qml clips, which would slice a card trying to grow upward out of
 * this pill. The sidebar's `PanelWindow` already runs
 * `WlrKeyboardFocus.OnDemand`, so escaping into its contentItem gets an
 * unclipped surface that a text field can still be typed into, without
 * opening a second Wayland surface -- compare `DockFolderPopup`, which needs
 * one only because the dock is a separate window.
 */
Item {
    id: root

    readonly property int percent: HermesService.contextPercent
    readonly property var breakdown: HermesService.contextBreakdown

    // Calm below 75%, then a warning tone, then error -- mirrors Resource.qml's
    // own threshold pattern for the bar's resource meters.
    readonly property color meterColor: root.percent >= 90 ? Appearance.colors.colError : root.percent >= 75 ? Appearance.colors.colTertiary : Appearance.colors.colOnSecondaryContainer

    readonly property string tooltipText: Translation.tr("%1 / %2 tokens used (%3%)").arg(HermesService.contextUsed).arg(HermesService.contextMax).arg(root.percent)

    // Category rows come from the agent's own accounting, so field names are
    // read tolerantly and a row that has neither a usable label nor a usable
    // count is dropped rather than printed as "undefined".
    function categoryLabel(row): string {
        return row?.name ?? row?.label ?? row?.category ?? "";
    }
    function categoryTokens(row): var {
        const raw = row?.tokens ?? row?.count ?? row?.size;
        return typeof raw === "number" ? raw : null;
    }
    function fileLabel(entry): string {
        if (typeof entry === "string")
            return entry;
        return entry?.path ?? entry?.name ?? entry?.file ?? "";
    }

    readonly property var categories: {
        const rows = root.breakdown?.categories ?? [];
        const out = [];
        for (const row of rows) {
            const label = root.categoryLabel(row);
            const tokens = root.categoryTokens(row);
            if (label.length === 0 || tokens === null)
                continue;
            out.push({
                "label": label,
                "tokens": tokens
            });
        }
        return out;
    }

    readonly property real maxCategoryTokens: {
        let max = 1;
        for (const category of root.categories)
            max = Math.max(max, category.tokens);
        return max;
    }

    readonly property var contextFiles: {
        const rows = root.breakdown?.context_files ?? [];
        const out = [];
        for (const entry of rows) {
            const label = root.fileLabel(entry);
            if (label.length > 0)
                out.push(label);
        }
        return out;
    }

    property Item popoverItem: null

    function togglePopover(): void {
        if (root.popoverItem) {
            root.closePopover();
            return;
        }
        const attached = root.QsWindow;
        if (!attached?.window || !attached?.contentItem)
            return;
        const pos = attached.window.itemPosition(pill);
        HermesService.refreshContextBreakdown();
        root.popoverItem = popoverComponent.createObject(attached.contentItem, {
            "anchorRect": Qt.rect(pos.x, pos.y, pill.width, pill.height)
        });
    }

    function closePopover(): void {
        const item = root.popoverItem;
        if (!item)
            return;
        root.popoverItem = null;
        item.dismiss();
    }

    // The popover is parented to the window, not to us, once it exists -- if
    // this page gets torn down (sidebar closed, content released) while it is
    // open, nothing else would ever destroy it.
    Component.onDestruction: root.popoverItem?.destroy()

    visible: root.percent > 0
    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    RippleButton {
        id: pill
        anchors.fill: parent
        horizontalPadding: 8
        implicitHeight: 30
        implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
        buttonRadius: Appearance.rounding.full
        toggled: root.popoverItem !== null
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundActive: Appearance.colors.colLayer2Active
        colBackgroundToggled: Appearance.colors.colLayer2Active
        colBackgroundToggledHover: Appearance.colors.colLayer2Active
        colRipple: Appearance.colors.colLayer2Active

        releaseAction: () => root.togglePopover()

        contentItem: RowLayout {
            anchors {
                verticalCenter: parent.verticalCenter
                left: parent.left
                right: parent.right
                leftMargin: pill.horizontalPadding
                rightMargin: pill.horizontalPadding
            }
            spacing: 6

            CircularProgress {
                Layout.alignment: Qt.AlignVCenter
                implicitSize: 16
                lineWidth: 2
                value: root.percent / 100
                colPrimary: root.meterColor
                colSecondary: Appearance.colors.colSecondaryContainer

                Behavior on colPrimary {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: Translation.tr("%1%").arg(root.percent)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.meterColor

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }

        StyledToolTip {
            text: root.tooltipText
            extraVisibleCondition: true
        }
    }

    Component {
        id: popoverComponent

        Item {
            id: overlay
            property rect anchorRect: Qt.rect(0, 0, 0, 0)

            anchors.fill: parent
            z: 1000

            function dismiss(): void {
                closeAnim.start();
            }

            Component.onCompleted: cardColumn.forceActiveFocus()

            // Anywhere off the card closes it, like any other popover.
            MouseArea {
                anchors.fill: parent
                onClicked: overlay.dismiss()
            }

            StyledRectangularShadow {
                target: card
                scale: card.scale
                transformOrigin: card.transformOrigin
                opacity: card.opacity
            }

            Rectangle {
                id: card

                readonly property real gutter: 8
                readonly property real gap: 10

                x: Math.max(gutter, Math.min(overlay.anchorRect.x + overlay.anchorRect.width / 2 - implicitWidth / 2, overlay.width - implicitWidth - gutter))
                // Clamped, unlike DockFolderPopup's own bottom-dock case: this
                // card's content is a lot taller than a folder name field, and
                // a short chat area would otherwise push it off the top edge.
                y: Math.max(gutter, overlay.anchorRect.y - implicitHeight - gap)

                implicitWidth: Math.min(340, overlay.width - gutter * 2)
                implicitHeight: cardColumn.implicitHeight + 12 * 2
                radius: Appearance.rounding.verylarge
                color: Appearance.colors.colLayer1Base

                opacity: 0
                scale: 0.5
                // Grows out of the pill that opened it, per ArrowPopup's pivot.
                transformOrigin: Item.Bottom

                // ArrowPopup.animateOpen(): scale 0.5 -> 1.02 over 200ms
                // emphasizedDecel, then settles 1.02 -> 1 over 200ms on
                // PathInterpolator(0.3, 0, 0.33, 1). Card fades in linearly
                // over 83ms. DockFolderPopup and DesktopMenu are this recipe's
                // other two callers.
                ParallelAnimation {
                    id: openAnim
                    running: true
                    SequentialAnimation {
                        NumberAnimation {
                            target: card
                            property: "scale"
                            from: 0.5
                            to: 1.02
                            duration: 200
                            easing.type: Easing.Bezier
                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                        }
                        NumberAnimation {
                            target: card
                            property: "scale"
                            to: 1
                            duration: 200
                            easing.type: Easing.Bezier
                            easing.bezierCurve: [0.3, 0, 0.33, 1, 1, 1]
                        }
                    }
                    NumberAnimation {
                        target: card
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 83
                    }
                }

                // ArrowPopup.animateClose(): scale 1 -> 0.5 over 233ms
                // emphasizedAccel, fade held back 150ms then out over 83ms.
                ParallelAnimation {
                    id: closeAnim
                    NumberAnimation {
                        target: card
                        property: "scale"
                        to: 0.5
                        duration: 233
                        easing.type: Easing.Bezier
                        easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                    }
                    SequentialAnimation {
                        PauseAnimation {
                            duration: 150
                        }
                        NumberAnimation {
                            target: card
                            property: "opacity"
                            to: 0
                            duration: 83
                        }
                    }
                    onFinished: overlay.destroy()
                }

                // Swallows what the dismiss handler underneath would otherwise take.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                ColumnLayout {
                    id: cardColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 12
                    }
                    spacing: 12

                    focus: true
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            event.accepted = true;
                            overlay.dismiss();
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Context window")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                text: Translation.tr("%1%").arg(root.percent)
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: root.meterColor
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("%1 / %2 tokens").arg(HermesService.contextUsed).arg(HermesService.contextMax)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.breakdown?.context_estimated === true
                            wrapMode: Text.Wrap
                            text: Translation.tr("~%1 tokens estimated -- not reported by the provider").arg(root.breakdown?.estimated_total ?? HermesService.contextUsed)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.breakdown === null
                        spacing: 8

                        MaterialLoadingIndicator {
                            implicitSize: 18
                            loading: true
                        }

                        StyledText {
                            text: Translation.tr("Loading breakdown…")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.categories.length > 0
                        spacing: 8

                        Repeater {
                            model: root.categories

                            delegate: ColumnLayout {
                                id: categoryRow
                                required property var modelData

                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        elide: Text.ElideRight
                                        text: categoryRow.modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer1
                                    }

                                    StyledText {
                                        text: categoryRow.modelData.tokens.toString()
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                                StyledProgressBar {
                                    Layout.fillWidth: true
                                    valueBarHeight: 6
                                    value: categoryRow.modelData.tokens / root.maxCategoryTokens
                                    highlightColor: Appearance.colors.colPrimary
                                    trackColor: Appearance.colors.colSecondaryContainer
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.contextFiles.length > 0
                        spacing: 4

                        StyledText {
                            text: Translation.tr("Loaded files")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        Repeater {
                            model: root.contextFiles

                            delegate: StyledText {
                                required property string modelData
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideMiddle
                                text: modelData
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.family: Appearance.font.family.monospace
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        RippleButton {
                            id: compressButton
                            Layout.alignment: Qt.AlignLeft
                            enabled: !HermesService.compressing && !HermesService.busy
                            horizontalPadding: 12
                            implicitHeight: 30
                            implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colPrimaryContainer
                            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                            colBackgroundActive: Appearance.colors.colPrimaryContainerActive
                            colRipple: Appearance.colors.colPrimaryContainerActive

                            releaseAction: () => HermesService.compressSession(focusField.text)

                            contentItem: RowLayout {
                                anchors {
                                    verticalCenter: parent.verticalCenter
                                    left: parent.left
                                    right: parent.right
                                    leftMargin: compressButton.horizontalPadding
                                    rightMargin: compressButton.horizontalPadding
                                }
                                spacing: 8

                                Loader {
                                    active: HermesService.compressing
                                    sourceComponent: MaterialLoadingIndicator {
                                        implicitSize: 16
                                        loading: true
                                    }
                                }
                                Loader {
                                    active: !HermesService.compressing
                                    sourceComponent: MaterialSymbol {
                                        text: "unfold_less"
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: Appearance.colors.colOnPrimaryContainer
                                    }
                                }

                                StyledText {
                                    text: Translation.tr("Fold conversation")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnPrimaryContainer
                                }
                            }
                        }

                        MaterialTextField {
                            id: focusField
                            Layout.fillWidth: true
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            placeholderText: Translation.tr("Focus the fold on… (optional)")
                        }
                    }
                }
            }
        }
    }
}
