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
 * One lock screen notification card: everything from one app.
 *
 * This is AOSP's 2025 notification redesign, the one that shipped on Pixel with
 * Android 16 QPR1. Every number is from `notification_2025_*` in
 * frameworks/base `core/res/res/values/dimens.xml`:
 *   72 tall collapsed (16 margin + 40 content + 16 margin), a 40 circular icon
 *   16 from the leading edge, content inset 72, trailing inset 16, corner
 *   radius 28 (`notification_corner_radius`), and a 24-tall expand pill with
 *   the group count in it (`notification_expand_button_pill_height`).
 *
 * Collapsed puts the *title* on the top line, not the app name - AOSP's
 * Builder hides `app_name_text` whenever the title is on that line, because the
 * icon already says which app it is. The app name comes back in the expanded
 * header, which is what `notification_2025_template_header` draws.
 *
 * Input arrives as resolved target strings from NotificationStackView, never
 * from a MouseArea in here - see the note in NotificationStackItem.
 */
Item {
    id: root

    required property var group // { appName, appIcon, notifications, time }
    property bool expanded: false
    property bool showActions: true
    property bool contentHidden: false
    property real fontScale: 1.0
    property real surfaceOpacity: 1.0

    // Swipe-to-dismiss. `swipeOffset` slides the whole card (a collapsed group
    // dismisses as one); `childSwipeId`/`childSwipeOffset` slide one child of
    // an expanded group, which is what AOSP dismisses once a group is open.
    // `swiping` means the offset is already being driven - by the pointer, or
    // by the view's fly-off/snap-back animation - so `x` must follow it exactly
    // rather than chase it through a second animation.
    property real swipeOffset: 0
    property bool swiping: false
    property int childSwipeId: -1
    property real childSwipeOffset: 0

    // 0 -> 1 unrolls the card, driven by the two animations below. `exiting` is
    // set by the view one animation before the group leaves its model, which is
    // the only reason there is anything left on screen to animate out.
    property real appearProgress: 1
    property int entryDelay: 0
    property bool animateEntry: true
    property bool exiting: false

    property string hoverTarget: ""
    property string pressTarget: ""

    readonly property var notifications: root.group?.notifications ?? []
    readonly property int count: root.notifications.length
    // Newest first: the service appends, so a group's own list runs oldest to
    // newest and this is the order the lock screen reads them in.
    readonly property var ordered: root.notifications.slice().reverse()
    readonly property var newest: root.ordered[0] ?? null
    readonly property bool grouped: root.count > 1
    readonly property bool urgent: root.notifications.some(n => n.urgency === NotificationUrgency.Critical.toString())

    // ── Metrics ──────────────────────────────────────────────────────────────
    // AOSP `notification_2025_margin`, `notification_2025_icon_circle_size`,
    // `notification_2025_content_margin_start`, `notification_content_margin_end`.
    readonly property real pad: 16
    readonly property real iconSize: 40
    readonly property real contentInset: 72
    // notification_2025_min_height: 16 * 2 margins + 40 content.
    readonly property real collapsedHeight: 72
    readonly property real cornerRadius: Appearance.rounding.large

    readonly property real infoSize: Appearance.font.pixelSize.smaller * root.fontScale

    // A card here sits directly on the wallpaper, so it needs a real colour:
    // `colBackgroundSurfaceContainer` is m3surfaceContainer with the *background*
    // transparency applied, and it is what NotificationPopup paints with for
    // exactly this reason. `colSurfaceContainerHigh`/`colLayer*` are
    // solveOverlayColor results - the colour to paint *over* a known base to
    // land on the target - so over bare wallpaper they solve against a surface
    // that is not there and wash out to grey.
    //
    // Anything nested *inside* the card is a different story: the card's base
    // is m3surfaceContainer, which is precisely the base
    // `colSurfaceContainerHigh` is solved against, so that token is correct
    // there and nowhere else in this widget.
    readonly property color colSurface: Appearance.colors.colBackgroundSurfaceContainer
    readonly property color colContent: Appearance.colors.colOnSurface
    readonly property color colContentVariant: Appearance.colors.colOnSurfaceVariant
    readonly property color colChildSurface: Appearance.colors.colSurfaceContainerHigh

    readonly property string timeString: {
        DateTime.clock.date; // re-read so a relative time keeps counting
        return NotificationUtils.getFriendlyNotifTimeString(root.group?.time);
    }

    // ── Height ───────────────────────────────────────────────────────────────
    readonly property real fullHeight: root.expanded
        ? expandedBody.y + expandedBody.height + root.pad
        : root.collapsedHeight
    implicitHeight: Math.max(0, root.fullHeight * root.appearProgress)
    // AOSP unrolls an appearing row from the top and clips the rest away
    // (ActivatableNotificationView.startAppearAnimation, ClipSide.BOTTOM).
    clip: true

    // Content fades in over the last 30% of the unroll:
    // ALPHA_APPEAR_START_FRACTION .7 -> ALPHA_APPEAR_END_FRACTION 1.
    readonly property real contentOpacity: Math.max(0, Math.min(1, (root.appearProgress - 0.7) / 0.3))

    SequentialAnimation {
        id: appearAnim
        running: false

        // AOSP staggers a batch by ANIMATION_DELAY_PER_ELEMENT_MANUAL (32),
        // capped at MAX_STAGGER_COUNT (5); the view does the capping.
        PauseAnimation {
            // `|| 0` because a delegate can evaluate this before the view has
            // assigned `index`, and NaN reaches PauseAnimation as a negative
            // duration it refuses.
            duration: Math.max(0, root.entryDelay || 0)
        }
        NumberAnimation {
            target: root
            property: "appearProgress"
            from: 0
            to: 1
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
        }
    }

    // Enter decelerating on default spatial, leave accelerating at half the
    // duration - the asymmetry is the point, the user has already decided.
    NumberAnimation {
        id: disappearAnim
        target: root
        property: "appearProgress"
        to: 0
        duration: Math.round(Appearance.animation.elementMoveEnter.duration / 2)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
    }

    onExitingChanged: {
        if (!root.exiting)
            return;
        appearAnim.stop();
        disappearAnim.start();
    }

    Component.onCompleted: {
        if (!root.animateEntry) {
            root.appearProgress = 1;
            return;
        }
        root.appearProgress = 0;
        appearAnim.start();
    }

    // AOSP SwipeHelper.getSwipeAlpha: 1 - progress / SWIPE_PROGRESS_FADE_END,
    // with SWIPE_PROGRESS_FADE_END 0.6 of the row's width.
    function swipeAlpha(offset: real): real {
        if (root.width <= 0)
            return 1;
        return Math.max(0, 1 - (Math.abs(offset) / root.width) / 0.6);
    }

    /**
     * What sits under (px, py) in this card's coordinates:
     *   "pill"                     the expand affordance
     *   "close"                    the dismiss glyph
     *   "child:<id>"               a child row of an expanded group
     *   "action:<id>:<identifier>" an action pill
     *   "body"                     the card itself
     */
    function hitTest(px: real, py: real): string {
        if (root.appearProgress < 0.5)
            return "";
        if (_inside(pillHit, px, py))
            return "pill";
        if (_inside(closeHit, px, py))
            return "close";
        if (root.expanded) {
            if (!root.grouped && singleLoader.item) {
                const p = root.mapToItem(singleLoader.item, px, py);
                const own = singleLoader.item.hitTest(p.x, p.y);
                if (own.length > 0)
                    return own;
            } else if (root.grouped && childrenLoader.item) {
                const rows = childrenLoader.item.children;
                for (let i = 0; i < rows.length; i++) {
                    const row = rows[i];
                    if (!row || !row.visible || row.notifId === undefined)
                        continue;
                    const p = root.mapToItem(row, px, py);
                    if (p.x < 0 || p.y < 0 || p.x > row.width || p.y > row.height)
                        continue;
                    const own = row.hitTest(p.x, p.y);
                    return own.length > 0 ? own : `child:${row.notifId}`;
                }
            }
        }
        return "body";
    }

    function _inside(item: Item, px: real, py: real): bool {
        if (!item || !item.visible)
            return false;
        const p = root.mapToItem(item, px, py);
        return p.x >= 0 && p.y >= 0 && p.x <= item.width && p.y <= item.height;
    }

    // Whether a horizontal drag that started on `target` takes the whole card
    // with it. A collapsed group goes as one; an open group loses one child at
    // a time, which is what SwipeDismissible's `interactive: !expanded` does
    // for the dashboard list.
    function swipesWholeCard(target: string): bool {
        return !(root.expanded && root.grouped);
    }

    Rectangle {
        id: background
        x: root.swipeOffset
        y: 0
        width: parent.width
        // Kept at full height so the parent's clip takes the bottom off as the
        // card unrolls, rather than squashing the content.
        height: root.fullHeight
        radius: root.cornerRadius
        color: ColorUtils.transparentize(root.colSurface, 1 - root.surfaceOpacity)
        opacity: root.swipeAlpha(root.swipeOffset)

        Behavior on x {
            enabled: !root.swiping
            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(background)
        }
        Behavior on height {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(background)
        }

        StateOverlay {
            anchors.fill: parent
            radius: background.radius
            contentColor: root.colContent
            hover: root.hoverTarget === "body" && root.pressTarget.length === 0
            press: root.pressTarget === "body"
            drag: root.swiping && root.swipeOffset !== 0
        }

        Item {
            id: contentRoot
            anchors.fill: parent
            opacity: root.contentOpacity

            // ── Header row ───────────────────────────────────────────────────
            Item {
                id: header
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: root.collapsedHeight

                NotificationAppIcon {
                    id: appIcon
                    x: root.pad
                    y: (header.height - height) / 2
                    implicitSize: root.iconSize
                    // notification_2025_icon_circle_padding is 8 of the 40, so
                    // the glyph inside the circle is 24.
                    materialIconScale: 0.6
                    appIconScale: 0.85
                    appIcon: root.group?.appIcon ?? ""
                    summary: root.newest?.summary ?? ""
                    urgency: root.urgent ? NotificationUrgency.Critical : NotificationUrgency.Normal
                }

                // Trailing column: the close glyph over the expand pill, the
                // way `notification_2025_template_header` stacks them. AOSP
                // shows the close button unconditionally; on a pointer it only
                // needs to be there once the row is under the cursor.
                Item {
                    id: closeHit
                    anchors.right: parent.right
                    anchors.top: parent.top
                    // notification_close_button_size is 16; the target around
                    // it is ours to size, and 28 keeps it clear of the pill.
                    width: 28
                    height: 24
                    visible: root.hoverTarget.length > 0 || root.pressTarget.length > 0

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 16
                        color: root.colContentVariant
                        opacity: (root.hoverTarget === "close" || root.pressTarget === "close") ? 1 : 0.5

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                }

                Item {
                    id: pillHit
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    y: (header.height - height) / 2
                    // A generous target around a 24-tall pill, matching AOSP's
                    // 16 horizontal padding on the expand button.
                    width: pill.width + 16
                    height: 40

                    Rectangle {
                        id: pill
                        anchors.centerIn: parent
                        height: 24
                        width: Math.max(24, pillRow.width + (root.grouped ? 12 : 0))
                        radius: Appearance.rounding.full
                        color: root.colChildSurface

                        StateOverlay {
                            anchors.fill: parent
                            radius: parent.radius
                            contentColor: root.colContent
                            hover: root.hoverTarget === "pill" && root.pressTarget !== "pill"
                            press: root.pressTarget === "pill"
                        }

                        Row {
                            id: pillRow
                            anchors.centerIn: parent
                            spacing: 0

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.grouped
                                // notification_expand_button_number paddingStart
                                leftPadding: 8
                                font.pixelSize: root.infoSize
                                color: root.colContent
                                text: root.count
                            }
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "keyboard_arrow_down"
                                // The 24 pill less notification_expand_button_icon_padding
                                iconSize: 20
                                color: root.colContent
                                rotation: root.expanded ? 180 : 0

                                Behavior on rotation {
                                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                                }
                            }
                        }
                    }
                }

                // The picture a notification can carry, opposite the text the
                // way AOSP puts `right_icon` at the trailing edge of a
                // collapsed row (48, notification_right_icon_content_margin 12).
                Loader {
                    id: rightIconLoader
                    anchors.right: pillHit.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    active: !root.expanded && !root.contentHidden && (root.newest?.image ?? "") !== ""
                    visible: active

                    sourceComponent: NotificationAppIcon {
                        implicitSize: 48
                        image: root.newest?.image ?? ""
                    }
                }

                Item {
                    id: contentSlot
                    x: root.contentInset
                    y: 0
                    width: Math.max(0, header.width - root.contentInset - root.pad
                        - pillHit.width - (rightIconLoader.active ? 60 : 0))
                    height: parent.height

                    Row { // App name • time, the expanded header's top line
                        id: appLine
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        spacing: 0
                        opacity: root.expanded ? 1 : 0
                        visible: opacity > 0

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(appLine)
                        }

                        TextMetrics {
                            // An eliding Text reports its *elided* width as
                            // implicitWidth once the layout gives it one, so
                            // the full string is measured separately.
                            id: appNameMetrics
                            font: appNameText.font
                            text: appNameText.text
                        }
                        StyledText {
                            id: appNameText
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, Math.min(Math.ceil(appNameMetrics.width) + 2, appLine.width - appTimeRow.width))
                            font.pixelSize: root.infoSize
                            color: root.colContentVariant
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            text: root.group?.appName ?? ""
                        }
                        Row {
                            id: appTimeRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            visible: root.timeString.length > 0

                            StyledText {
                                leftPadding: 4
                                rightPadding: 4
                                font.pixelSize: root.infoSize
                                color: root.colContentVariant
                                text: "•"
                            }
                            StyledText {
                                font.pixelSize: root.infoSize
                                color: root.colContentVariant
                                text: root.timeString
                            }
                        }
                    }

                    NotificationStackItem { // Collapsed content
                        id: collapsedItem
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        visible: opacity > 0
                        opacity: root.expanded ? 0 : 1
                        notif: root.newest
                        expanded: false
                        showActions: false
                        contentHidden: root.contentHidden
                        fontScale: root.fontScale
                        colContent: root.colContent
                        colContentVariant: root.colContentVariant

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(collapsedItem)
                        }
                    }
                }
            }

            // ── Expanded body ────────────────────────────────────────────────
            Item {
                id: expandedBody
                x: 0
                y: header.height
                width: background.width
                height: {
                    if (!root.expanded)
                        return 0;
                    if (root.grouped)
                        return childrenLoader.item?.height ?? 0;
                    return singleLoader.item?.height ?? 0;
                }
                visible: root.expanded && height > 0
                clip: true

                Loader { // A lone notification opens into its own full body
                    id: singleLoader
                    x: root.contentInset
                    width: Math.max(0, background.width - root.contentInset - root.pad)
                    active: root.expanded && !root.grouped

                    sourceComponent: NotificationStackItem {
                        notif: root.newest
                        expanded: true
                        showActions: root.showActions
                        contentHidden: root.contentHidden
                        fontScale: root.fontScale
                        hoverTarget: root.hoverTarget
                        pressTarget: root.pressTarget
                        colContent: root.colContent
                        colContentVariant: root.colContentVariant
                        colActionSurface: root.colChildSurface
                    }
                }

                Loader { // A group opens into one row per notification
                    id: childrenLoader
                    width: expandedBody.width
                    active: root.expanded && root.grouped

                    sourceComponent: Column {
                        // notification_children_padding
                        spacing: 4
                        bottomPadding: 8

                        Repeater {
                            model: root.ordered

                            delegate: Rectangle {
                                id: childRow
                                required property var modelData
                                required property int index

                                readonly property int notifId: childRow.modelData?.notificationId ?? -1
                                readonly property real offset: root.childSwipeId === childRow.notifId ? root.childSwipeOffset : 0

                                function hitTest(px: real, py: real): string {
                                    return childItem.hitTest(px - childItem.x, py - childItem.y);
                                }

                                x: 8 + childRow.offset
                                width: expandedBody.width - 16
                                height: childItem.implicitHeight + 16
                                radius: Appearance.rounding.small
                                color: root.colChildSurface
                                opacity: root.swipeAlpha(childRow.offset)

                                Behavior on x {
                                    enabled: !root.swiping
                                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(childRow)
                                }

                                StateOverlay {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    contentColor: root.colContent
                                    hover: root.hoverTarget === `child:${childRow.notifId}` && root.pressTarget.length === 0
                                    press: root.pressTarget === `child:${childRow.notifId}`
                                    drag: root.swiping && childRow.offset !== 0
                                }

                                NotificationStackItem {
                                    id: childItem
                                    // Padded to its own block rather than
                                    // inset to `contentInset` to line up with
                                    // the header text. AOSP can afford that
                                    // inset because its expanded group children
                                    // each carry their own leading icon; these
                                    // do not - a group is one app, so the icon
                                    // would say the same thing N times over -
                                    // which left the column holding nothing.
                                    x: root.pad
                                    y: 8
                                    width: Math.max(0, childRow.width - root.pad * 2)
                                    notif: childRow.modelData
                                    expanded: false
                                    showActions: false
                                    contentHidden: root.contentHidden
                                    fontScale: root.fontScale
                                    colContent: root.colContent
                                    colContentVariant: root.colContentVariant
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
