import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import "./cards"

MouseArea {
    id: indicator
    property bool vertical: false

    // Held one step behind the service: the chips have to stay on screen while
    // the pill closes over them, or the exit is just a blank box shrinking.
    property var entries: []
    readonly property bool active: PrivacyMonitor.entries.length > 0

    Connections {
        target: PrivacyMonitor
        function onEntriesChanged() {
            if (PrivacyMonitor.entries.length > 0)
                indicator.entries = PrivacyMonitor.entries;
        }
    }
    readonly property int chipSize: 24

    // Fixed like Android's own chip: green for what is recording you, blue for
    // location, so the meaning doesn't shift when the wallpaper theme does.
    readonly property var chipColors: ({
            "microphone": ["#10DB5C", "#00450E"],
            "camera": ["#10DB5C", "#00450E"],
            "screen": ["#10DB5C", "#00450E"],
            "location": ["#1589FA", "#00136E"]
        })
    readonly property var chipIcons: ({
            "microphone": "mic",
            "camera": "photo_camera",
            "screen": "screen_share",
            "location": "location_on"
        })

    readonly property int chipPadding: 4

    hoverEnabled: true
    clip: true
    // Sized off the layout, not off the pill: the pill fills this item, so
    // taking its size back would be a binding loop.
    implicitWidth: indicator.openness > 0 ? contentLayout.implicitWidth + indicator.chipPadding * 2 : 0
    implicitHeight: indicator.openness > 0 ? contentLayout.implicitHeight + indicator.chipPadding * 2 : 0

    // DESIGN 2.9: a Behavior cannot read its own direction from a sibling
    // binding, so the spec is assigned inside the binding everything else
    // depends on -- that one runs first by construction.
    property real transitionDuration: Appearance.animation.elementMoveEnter.duration
    property var transitionCurve: Appearance.animation.elementMoveEnter.bezierCurve
    readonly property real openness: {
        // Springy expand on the way in; the exit accelerates away at the effects
        // duration instead, since the effects curves front-load so hard the
        // collapse was over in ~70ms of its 200 (DESIGN 2.5).
        indicator.transitionDuration = indicator.active ? Appearance.animation.elementMoveEnter.duration : Appearance.animation.elementMoveFast.duration;
        indicator.transitionCurve = indicator.active ? Appearance.animation.elementMoveEnter.bezierCurve : Appearance.animationCurves.emphasizedAccel;
        return indicator.active ? 1 : 0;
    }

    // The pill widens out of nothing and snaps back shut, so it can't just be
    // shown and hidden: stay around until the closing animation lands on zero.
    // `clip` above means the width alone hides it -- an extra opacity fade would
    // have to overshoot on this spatial curve, which DESIGN 0.3 forbids.
    Behavior on implicitWidth {
        animation: indicator.transitionAnimation.createObject(indicator)
    }
    Behavior on implicitHeight {
        animation: indicator.transitionAnimation.createObject(indicator)
    }

    readonly property Component transitionAnimation: Component {
        NumberAnimation {
            duration: indicator.transitionDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: indicator.transitionCurve
        }
    }

    // toggleVisible writes the bar layout back to disk, so only call it on a
    // real change.
    function setVisible(shown) {
        if (rootItem.visible !== shown)
            rootItem.toggleVisible(shown);
    }

    Component.onCompleted: {
        indicator.entries = PrivacyMonitor.entries;
        indicator.setVisible(indicator.active);
    }
    onActiveChanged: if (indicator.active)
        indicator.setVisible(true)
    onImplicitWidthChanged: if (!indicator.active && indicator.implicitWidth === 0) {
        indicator.setVisible(false);
        indicator.entries = [];
    }

    function iconFor(kind) {
        return indicator.chipIcons[kind];
    }

    function labelFor(kind) {
        if (kind === "microphone")
            return Translation.tr("Microphone");
        if (kind === "camera")
            return Translation.tr("Camera");
        if (kind === "screen")
            return Translation.tr("Screen sharing");
        return Translation.tr("Location");
    }

    function usageFor(kind) {
        if (kind === "microphone")
            return Translation.tr("is using your microphone");
        if (kind === "camera")
            return Translation.tr("is using your camera");
        if (kind === "screen")
            return Translation.tr("is sharing your screen");
        return Translation.tr("is using your location");
    }

    // The chips carry the meaning, so they sit on a neutral pill of their own
    // instead of tinting the whole bar group.
    Rectangle {
        id: pill
        anchors.fill: parent
        radius: Appearance.rounding.full
        // One layer above the bar group it sits on, with that layer's own hover
        // film rather than a hand-mixed tint (DESIGN 6.1, 3.1). There is no
        // pressed film because the chip has no click action -- hovering is the
        // whole interaction -- and painting one would advertise an action that
        // does not exist.
        color: indicator.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    GridLayout {
        id: contentLayout
        anchors.centerIn: parent
        flow: indicator.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: indicator.vertical ? indicator.entries.length + 1 : 1
        columns: indicator.vertical ? 1 : indicator.entries.length + 1
        rowSpacing: 2
        columnSpacing: 2

        Repeater {
            model: indicator.entries
            delegate: Rectangle {
                id: chip
                required property var modelData
                implicitWidth: indicator.chipSize
                implicitHeight: indicator.chipSize
                radius: Appearance.rounding.full
                color: indicator.chipColors[modelData.kind][0]

                // Each sensor pops in on its own, so a second one lighting up
                // in an open pill still reads as an event, and they shrink
                // away together as the pill closes over them.
                property bool grown: false
                Component.onCompleted: chip.grown = true
                scale: (chip.grown && indicator.openness > 0) ? 1 : 0
                Behavior on scale {
                    animation: indicator.transitionAnimation.createObject(chip)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: indicator.iconFor(modelData.kind)
                    fill: 1
                    iconSize: indicator.chipSize - 8
                    color: indicator.chipColors[modelData.kind][1]
                }
            }
        }

        MaterialSymbol {
            text: "chevron_right"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnSurfaceVariant
            // Points along the bar, then turns towards the details as they open.
            rotation: (indicator.vertical ? 90 : 0) + 90 * popup.popupOpenProgress
        }
    }

    StyledPopup {
        id: popup
        hoverTarget: indicator
        contentItem: ColumnLayout {
            anchors.centerIn: parent
            spacing: 8

            Repeater {
                model: indicator.entries
                delegate: SectionCard {
                    id: kindCard
                    required property var modelData
                    icon: indicator.iconFor(modelData.kind)
                    title: indicator.labelFor(modelData.kind)
                    shapeColor: indicator.chipColors[modelData.kind][0]
                    symbolColor: indicator.chipColors[modelData.kind][1]
                    headerExtraText: modelData.kind === "screen" ? Translation.tr("Sharing") : Translation.tr("In use")
                    // GeoClue only tells a client its own name, so an app that
                    // talks to it over raw D-Bus stays anonymous.
                    subtitle: modelData.apps.length > 0 ? "" : Translation.tr("An unidentified app %1").arg(indicator.usageFor(modelData.kind))
                    spacing: 6

                    Repeater {
                        model: modelData.apps
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8

                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: `${modelData.name} ${indicator.usageFor(kindCard.modelData.kind)}`
                                color: Appearance.colors.colOnSurface
                            }
                            StyledText {
                                // The name already says which process it is, so
                                // only the pid adds anything here.
                                visible: modelData.pid > 0
                                text: `PID ${modelData.pid}`
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                }
            }
        }
    }
}
