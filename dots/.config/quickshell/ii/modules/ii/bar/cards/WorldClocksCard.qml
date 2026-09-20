import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.animations
import qs.services

Item {
    id: root

    property var timezoneOffsets: ({})

    // Functions mapped from parent ClockWidgetPopup
    property var getTimezoneOffsetString
    property var getUtcTimeForTz
    property var getFormattedTime
    property var getFormattedDate
    
    // Internal animation control
    property bool startAnim: false

    // The card enters as one thing -- opacity on an effects spec plus one
    // transform on the enter spec (DESIGN.md 2.1, 2.5). Its icon, offset badge
    // and clock used to each enter separately, inside a card that is itself
    // entering inside a popup that is itself scaling open.
    readonly property int enterTravel: 24

    onStartAnimChanged: {
        if (!root.startAnim) return;
        for (let i = 0; i < listView.count; i++) {
            const item = listView.itemAtIndex(i);
            if (!item) continue;
            item.cardOpacity = 0.0;
            item.cardTranslateX = root.enterTravel;
        }
        Qt.callLater(() => {
            for (let j = 0; j < listView.count; j++) {
                const card = listView.itemAtIndex(j);
                if (!card) continue;
                // staggerStep apart, capped (DESIGN.md 2.8).
                card.cardAnimDelay = Appearance.animation.staggerStep * Math.min(j, Appearance.animation.staggerCap);
                card.startCardAnim();
            }
        });
    }

    Layout.fillWidth: true
    Layout.preferredHeight: 96
    implicitHeight: 96

    ListView {
        id: listView
        anchors.fill: parent
        orientation: ListView.Horizontal
        spacing: 12
        clip: true
        interactive: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        model: Config.options.time.worldClocks

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                let delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                listView.contentX = Math.max(0, Math.min(listView.contentWidth - listView.width, listView.contentX - delta));
            }
        }

        delegate: Rectangle {
            id: card
            width: listView.count >= 2 ? (listView.width > 0 ? listView.width * 0.85 : 320) : (listView.width > 0 ? listView.width : 380)
            height: 96
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer2
            clip: true

            required property var modelData
            required property int index

            // Animation properties
            property real cardOpacity: 1.0
            property real cardTranslateX: 0
            property int cardAnimDelay: 0

            function startCardAnim() {
                cardAnim.restart();
            }

            ParallelAnimation {
                id: cardAnim

                DelayedPropertyAnimation {
                    target: card
                    property: "cardOpacity"
                    from: 0
                    to: 1
                    delay: card.cardAnimDelay
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
                DelayedPropertyAnimation {
                    target: card
                    property: "cardTranslateX"
                    from: root.enterTravel
                    to: 0
                    delay: card.cardAnimDelay
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Appearance.animation.elementMoveEnter.type
                    easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                }
            }

            opacity: card.cardOpacity
            transform: Translate {
                x: card.cardTranslateX
            }

            // Decorative blob behind the day/night glyph. It used to be an
            // oversized circle bled past the card's corners and clipped back with
            // a per-delegate layer + OpacityMask -- an extra framebuffer for every
            // world clock on screen (DESIGN.md 8, law 8). Native per-corner radii
            // do the same read with no effect at all: round on the inside, the
            // card's own corners on the outside.
            Rectangle {
                id: dayNightBlob
                // Twice the glyph column's inset from the right edge, so the
                // glyph sits dead centre in the blob at any card height.
                width: card.height * 1.32
                anchors {
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                }
                color: Appearance.colors.colLayer3
                // rounding.scale is 0 in sharp mode, so the blob flattens with
                // everything else instead of keeping a lone arc.
                topLeftRadius: Appearance.rounding.scale * dayNightBlob.height / 2
                bottomLeftRadius: dayNightBlob.topLeftRadius
                topRightRadius: card.radius
                bottomRightRadius: card.radius
            }

            // Right side weather/day-night info inside the circle
            ColumnLayout {
                anchors {
                    horizontalCenter: parent.right
                    horizontalCenterOffset: -card.height * 0.66
                    verticalCenter: parent.verticalCenter
                }
                spacing: 2

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        try {
                            const targetUtc = root.getUtcTimeForTz(card.modelData.tz, DateTime.clock.date);
                            if (isNaN(targetUtc)) return "question_mark";
                            const targetDate = new Date(targetUtc);
                            const hour = targetDate.getUTCHours();
                            return (hour < 6 || hour >= 18) ? "dark_mode" : "light_mode";
                        } catch (e) {
                            return "question_mark";
                        }
                    }
                    iconSize: card.height * 0.58
                    fill: 1
                    color: text === "light_mode" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "18°" // Mock placeholder temperature
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurface
                }
            }

            // Left side time zone info
            ColumnLayout {
                anchors {
                    left: parent.left
                    leftMargin: 20
                    verticalCenter: parent.verticalCenter
                }
                spacing: 6

                RowLayout {
                    spacing: 8

                    // Offset pill badge
                    Rectangle {
                        implicitWidth: offsetText.implicitWidth + 16
                        implicitHeight: 20
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSurfaceContainerHighest

                        StyledText {
                            id: offsetText
                            anchors.centerIn: parent
                            text: {
                                let offset = root.getTimezoneOffsetString(card.modelData.tz, DateTime.clock.date);
                                return offset === "" ? "+0h" : offset;
                            }
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Thin
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    StyledText {
                        text: card.modelData.name || card.modelData.tz || Translation.tr("Unnamed")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                    }
                }

                StyledText {
                    text: root.getFormattedTime(card.modelData.tz, DateTime.clock.date)
                    font.pixelSize: Math.min(42, card.width * 0.11)
                    font.family: Appearance.font.family.title
                    font.weight: 1000
                    color: Appearance.colors.colOnSurface
                }
            }
        }
    }
}
