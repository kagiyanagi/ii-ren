pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Composer status pill: how much of the plan's limits is spent -- the window
 * nearest its cap, as a ring -- and a tap-through to every window the agent
 * reports (5-hour, weekly, per model group), when each resets, and whether it
 * is being spent faster than it refills.
 *
 * The limits are the agent's own account of itself (AgentService "Plan
 * limits"), never read from a login. With none reported -- an API-key login has
 * no plan -- there is no pill. It replaced the context-window pill on purpose:
 * the plan is what runs out, and /compact still folds a long chat.
 *
 * The card is a AgentPopover, drawn from the sidebar window's content item
 * because `inputWrapper` in Agent.qml clips.
 */
Item {
    id: root

    readonly property var windows: AgentService.limitWindows
    readonly property bool hasLimits: root.windows.length > 0
    // The window nearest its cap among those that limit the model in use: an
    // Antigravity chat on Gemini is not held back by its Claude allowance.
    readonly property var nearest: {
        let best = null;
        for (const window of root.windows) {
            if (window.counts && (best === null || window.used > best.used))
                best = window;
        }
        return best ?? root.windows[0] ?? null;
    }
    readonly property int percent: root.nearest?.used ?? 0
    readonly property color meterColor: root.toneFor(root.percent)

    // Groups in the agent's order, each with its windows. One unnamed group for
    // an agent with a single allowance.
    readonly property var groups: {
        const out = [];
        for (const window of root.windows) {
            let group = out.find(entry => entry.name === (window.group ?? ""));
            if (!group) {
                group = { "name": window.group ?? "", "windows": [] };
                out.push(group);
            }
            group.windows.push(window);
        }
        return out;
    }

    // Calm below 75%, then a warning tone, then error -- mirrors Resource.qml's
    // own threshold pattern for the bar's resource meters.
    function toneFor(used: int): color {
        return used >= 90 ? Appearance.colors.colError : used >= 75 ? Appearance.colors.colTertiary : Appearance.colors.colOnSecondaryContainer;
    }
    function barTone(used: int): color {
        return used >= 90 ? Appearance.colors.colError : used >= 75 ? Appearance.colors.colTertiary : Appearance.colors.colPrimary;
    }

    // "Resets in" has to stay true while it is on screen, so the pill keeps a
    // clock -- a minute's resolution is all the copy has.
    property real now: Date.now()
    Timer {
        interval: 30000
        repeat: true
        running: root.visible && root.hasLimits
        onTriggered: root.now = Date.now()
    }

    function duration(ms: real): string {
        const minutes = Math.max(1, Math.round(ms / 60000));
        const days = Math.floor(minutes / 1440);
        const hours = Math.floor((minutes % 1440) / 60);
        if (days > 0)
            return hours > 0 ? Translation.tr("%1d %2h").arg(days).arg(hours) : Translation.tr("%1d").arg(days);
        if (hours > 0)
            return minutes % 60 > 0 ? Translation.tr("%1h %2m").arg(hours).arg(minutes % 60) : Translation.tr("%1h").arg(hours);
        return Translation.tr("%1m").arg(minutes);
    }
    function resetText(window): string {
        if (!window?.resets_at)
            return "";
        const left = window.resets_at * 1000 - root.now;
        return left <= 0 ? Translation.tr("Resets now") : Translation.tr("Resets in %1").arg(root.duration(left));
    }
    // How much of the window has gone by, 0-1; -1 when its length is unknown.
    function elapsed(window): real {
        if (!window?.resets_at || !window?.minutes)
            return -1;
        const span = window.minutes * 60000;
        return Math.max(0, Math.min(1, 1 - (window.resets_at * 1000 - root.now) / span));
    }
    // T3 Code's reading: more than 5 points past an even spend is ahead of pace.
    function paceText(window): string {
        const gone = root.elapsed(window);
        if (gone < 0)
            return "";
        const gap = window.used - gone * 100;
        return gap > 5 ? Translation.tr("ahead of pace") : gap < -5 ? Translation.tr("under pace") : Translation.tr("on pace");
    }

    readonly property string tooltipText: {
        if (!root.nearest)
            return "";
        const reset = root.resetText(root.nearest);
        const line = Translation.tr("%1 limit: %2% used").arg(root.nearest.label).arg(root.nearest.used);
        return reset.length > 0 ? `${line} · ${reset}` : line;
    }

    function togglePopover(): void {
        if (!popover.shown) {
            root.now = Date.now();
            AgentService.refreshUsageLimits(true);
        }
        popover.toggle(pill);
    }

    visible: root.hasLimits
    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    RippleButton {
        id: pill
        anchors.fill: parent
        horizontalPadding: 8
        implicitHeight: 30
        implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
        buttonRadius: Appearance.rounding.full
        toggled: popover.shown
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
                font.family: Appearance.font.family.numbers
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.meterColor

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
        }

        StyledToolTip {
            text: root.tooltipText
            extraVisibleCondition: !popover.shown // not over its own open card
        }
    }

    // One window: its name and share, the share as a bar with a mark where an
    // even spend would be by now, and when it starts over.
    component LimitRow: ColumnLayout {
        id: limitRow
        required property var modelData
        readonly property real gone: root.elapsed(limitRow.modelData)

        Layout.fillWidth: true
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                elide: Text.ElideRight
                text: limitRow.modelData.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurface
            }

            StyledText {
                text: Translation.tr("%1% used").arg(limitRow.modelData.used)
                font.family: Appearance.font.family.numbers
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: limitRow.modelData.used >= 75 ? root.toneFor(limitRow.modelData.used) : Appearance.colors.colSubtext
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: limitBar.implicitHeight + 4

            StyledProgressBar {
                id: limitBar
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                valueBarHeight: 6
                value: limitRow.modelData.used / 100
                highlightColor: root.barTone(limitRow.modelData.used)
                trackColor: Appearance.colors.colSecondaryContainer
            }

            Rectangle { // Where an even spend would have reached by now
                visible: limitRow.gone >= 0
                width: 2
                height: parent.height
                radius: Appearance.rounding.full
                x: Math.max(0, Math.min(parent.width - width, parent.width * limitRow.gone - width / 2))
                color: Appearance.colors.colOnSurface
                opacity: 0.6
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: text.length > 0
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
            text: {
                const reset = root.resetText(limitRow.modelData);
                const pace = root.paceText(limitRow.modelData);
                return reset.length > 0 && pace.length > 0 ? `${reset} · ${pace}` : reset || pace;
            }
        }
    }

    // Hangs from the pill's top centre and opens upward, out of the composer.
    AgentPopover {
        id: popover
        opensUp: true
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Plan usage")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurface
            }

            StyledText {
                visible: text.length > 0
                text: AgentService.usageLimits?.plan ?? ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        Repeater {
            model: root.groups

            delegate: ColumnLayout {
                id: groupBlock
                required property var modelData

                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    visible: groupBlock.modelData.name.length > 0
                    text: groupBlock.modelData.name
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colSubtext
                }

                Repeater {
                    model: groupBlock.modelData.windows
                    delegate: LimitRow {}
                }
            }
        }

        Repeater { // What the windows cannot say: free resets, extra credit
            model: AgentService.usageLimits?.notes ?? []

            delegate: StyledText {
                required property string modelData
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: modelData
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }
}
