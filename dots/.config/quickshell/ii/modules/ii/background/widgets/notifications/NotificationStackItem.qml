pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

/**
 * One notification's content, laid out the way Android's 2025 notification
 * template does (AOSP `notification_2025_template_collapsed_base.xml` and
 * `..._expanded_base.xml`):
 *
 *   collapsed  [ title • time ]        <- app name is deliberately absent; the
 *              [ body, one line ]        icon identifies the app, and the
 *                                        Builder hides app_name when a title
 *                                        is shown on the top line
 *   expanded   [ title ]
 *              [ body, wrapped ]
 *              [ action pills ]
 *
 * No MouseArea anywhere in here on purpose. A session lock surface sits above
 * every layer shell, so a widget drawn on the desktop plane never sees the lock
 * screen's pointer - the same reason AbstractBackgroundWidget drives its drag
 * from scene coordinates. Interaction arrives as `hoverTarget`/`pressTarget`
 * strings resolved by NotificationStackView's single gesture layer, and
 * `hitTest()` is how this item answers "what is under that point".
 */
Item {
    id: root

    required property var notif
    // Collapsed shows one line of body and no actions; expanded wraps the body
    // and reveals the action pills.
    property bool expanded: false
    property bool showActions: true
    // Lock screen privacy: the body is replaced by AOSP's public-version text.
    property bool contentHidden: false
    property real fontScale: 1.0
    // Resolved by the view and read back here, so press and hover render
    // without this item owning any input.
    property string hoverTarget: ""
    property string pressTarget: ""
    property color colContent: Appearance.colors.colOnSurface
    property color colContentVariant: Appearance.colors.colOnSurfaceVariant
    property color colActionSurface: Appearance.colors.colSurfaceContainerHighest

    readonly property int notifId: root.notif?.notificationId ?? -1
    readonly property bool urgent: (root.notif?.urgency ?? "") === NotificationUrgency.Critical.toString()
    readonly property string summaryText: root.notif?.summary ?? ""
    readonly property string bodyText: {
        if (root.contentHidden)
            return "";
        const raw = root.notif?.body ?? "";
        if (raw.length === 0)
            return "";
        return NotificationUtils.processNotificationBody(raw, root.notif?.appName ?? root.summaryText);
    }
    readonly property var actions: root.showActions ? (root.notif?.actions ?? []) : []
    readonly property bool hasImage: (root.notif?.image ?? "") !== ""

    // AOSP `notification_text_size` / `notification_title_text_size` are both
    // 14sp, `notification_subtext_size` (info, time) is 12sp.
    readonly property real titleSize: Appearance.font.pixelSize.small * root.fontScale
    readonly property real bodySize: Appearance.font.pixelSize.small * root.fontScale
    readonly property real infoSize: Appearance.font.pixelSize.smaller * root.fontScale

    implicitHeight: content.implicitHeight

    /**
     * Which part of this item sits under (px, py), given in this item's own
     * coordinates. Returns a target string the view can act on, or "" for the
     * inert parts of the row.
     */
    function hitTest(px: real, py: real): string {
        if (root.expanded && root.actions.length > 0) {
            for (let i = 0; i < actionRow.children.length; i++) {
                const pill = actionRow.children[i];
                if (!pill || !pill.visible || pill.hitId === undefined)
                    continue;
                const p = root.mapToItem(pill, px, py);
                if (p.x >= 0 && p.y >= 0 && p.x <= pill.width && p.y <= pill.height)
                    return pill.hitId;
            }
        }
        return "";
    }

    Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        // AOSP stacks the top line and the text with no gap of its own; the
        // line heights carry the rhythm (notification_headerless_line_height).
        spacing: 0

        Row { // Top line: title, separator, time
            id: topLine
            width: parent.width
            spacing: 0
            // notification_2025_content_min_height, so a one-line collapsed
            // notification still measures 40 and the card lands on 72.
            height: root.expanded ? titleText.implicitHeight : Math.max(titleText.implicitHeight, 20)

            TextMetrics {
                // An eliding Text reports its *elided* width as implicitWidth
                // once the layout gives it one, so the full string has to be
                // measured separately or the title collapses to "a...".
                id: titleMetrics
                font: titleText.font
                text: titleText.text
            }
            StyledText {
                id: titleText
                // +2 guards the sub-pixel rounding between what TextMetrics
                // measures and what the renderer needs: sized to the metric
                // exactly, every title elides to "K..." on the last glyph.
                width: Math.max(0, Math.min(Math.ceil(titleMetrics.width) + 2, topLine.width - timeRow.width))
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: root.titleSize
                font.variableAxes: Appearance.font.variableAxes.title
                color: root.colContent
                elide: Text.ElideRight
                maximumLineCount: 1
                text: root.contentHidden ? Translation.tr("Contents hidden") : root.summaryText
            }

            Row {
                id: timeRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                visible: !root.expanded && timeText.text.length > 0

                StyledText {
                    // AOSP `notification_header_divider_symbol`, with
                    // notification_header_separating_margin (2dp) either side.
                    leftPadding: 4
                    rightPadding: 4
                    font.pixelSize: root.infoSize
                    color: root.colContentVariant
                    text: "•"
                }
                StyledText {
                    id: timeText
                    font.pixelSize: root.infoSize
                    color: root.colContentVariant
                    text: {
                        DateTime.clock.date; // re-read so "5m" keeps counting
                        return NotificationUtils.getFriendlyNotifTimeString(root.notif?.time);
                    }
                }
            }
        }

        StyledText { // Body
            id: bodyTextItem
            width: parent.width
            visible: root.bodyText.length > 0
            // notification_headerless_line_height when collapsed.
            height: visible ? (root.expanded ? implicitHeight : 20) : 0
            font.pixelSize: root.bodySize
            color: root.colContentVariant
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: root.expanded ? 8 : 1
            textFormat: root.expanded ? Text.RichText : Text.StyledText
            text: root.expanded
                ? `<style>img{max-width:${Math.max(1, bodyTextItem.width)}px;}</style>${root.bodyText.replace(/\n/g, "<br/>")}`
                : root.bodyText

            Behavior on height {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(bodyTextItem)
            }
        }

        Item { // Actions
            width: parent.width
            height: root.expanded && root.actions.length > 0 ? actionRow.height + 12 : 0
            visible: height > 0
            clip: true

            Behavior on height {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Row {
                id: actionRow
                y: 12
                spacing: 8
                // AOSP `notification_action_list_height` is 60 with 36 buttons;
                // the pill radius is notification_action_button_radius (18).
                height: 36

                Repeater {
                    model: root.actions

                    delegate: Rectangle {
                        id: actionPill
                        required property var modelData
                        required property int index

                        readonly property string hitId: `action:${root.notifId}:${actionPill.modelData.identifier}`
                        readonly property bool isHovered: root.hoverTarget === actionPill.hitId
                        readonly property bool isPressed: root.pressTarget === actionPill.hitId

                        height: actionRow.height
                        width: actionLabel.implicitWidth + 32
                        radius: Appearance.rounding.full
                        color: root.colActionSurface

                        StateOverlay {
                            anchors.fill: parent
                            radius: parent.radius
                            contentColor: root.colContent
                            hover: actionPill.isHovered && !actionPill.isPressed
                            press: actionPill.isPressed
                        }

                        StyledText {
                            id: actionLabel
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, 180)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font.pixelSize: root.infoSize
                            font.variableAxes: Appearance.font.variableAxes.title
                            color: root.colContent
                            text: actionPill.modelData.text ?? ""
                        }
                    }
                }
            }
        }
    }
}
