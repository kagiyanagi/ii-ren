import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell.Io
import "./cards"

MouseArea {
    id: indicator
    property bool vertical: false

    readonly property int pillWidth: 40

    property bool activelyScreenSharing: false

    hoverEnabled: true
    clip: true
    implicitWidth: indicator.openness > 0 ? indicator.pillWidth : 0
    implicitHeight: indicator.openness > 0 ? Appearance.sizes.barHeight : 0

    // DESIGN 2.9: a Behavior cannot read its own direction from a sibling
    // binding, so the spec is assigned inside the binding the sizes depend on --
    // that one runs first by construction. Enter on the spatial enter spec, exit
    // accelerating at the effects duration (DESIGN 2.5).
    property real transitionDuration: Appearance.animation.elementMoveEnter.duration
    property var transitionCurve: Appearance.animation.elementMoveEnter.bezierCurve
    readonly property real openness: {
        indicator.transitionDuration = indicator.activelyScreenSharing ? Appearance.animation.elementMoveEnter.duration : Appearance.animation.elementMoveFast.duration;
        indicator.transitionCurve = indicator.activelyScreenSharing ? Appearance.animation.elementMoveEnter.bezierCurve : Appearance.animationCurves.emphasizedAccel;
        return indicator.activelyScreenSharing ? 1 : 0;
    }

    readonly property Component transitionAnimation: Component {
        NumberAnimation {
            duration: indicator.transitionDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: indicator.transitionCurve
        }
    }

    // The bar drops a widget by flipping `visible`, which snaps. Close over the
    // content first and only leave the layout once there is nothing left to show.
    Behavior on implicitWidth {
        animation: indicator.transitionAnimation.createObject(indicator)
    }
    Behavior on implicitHeight {
        animation: indicator.transitionAnimation.createObject(indicator)
    }

    onActivelyScreenSharingChanged: if (indicator.activelyScreenSharing)
        rootItem.toggleVisible(true)
    onImplicitWidthChanged: if (!indicator.activelyScreenSharing && indicator.implicitWidth === 0)
        rootItem.toggleVisible(false)

    Component.onCompleted: {
        // An alert pill of its own, not a tile in the tray's run.
        rootItem.isolated = true;
        rootItem.toggleHighlight(true);
    }

    // Sharing your screen is the error-family signal the brief calls for; the
    // bar's accent fill belongs to the workspaces. Bound rather than assigned
    // once, so it follows a wallpaper theme change.
    Binding {
        target: rootItem
        property: "customHighlightColor"
        value: Appearance.colors.colErrorContainer
    }

    Process {
        id: screenShareProc
        running: true
        command: ["bash", "-c", Directories.screenshareStateScript]
    }

    FileView {
        id: stateFile
        path: Directories.screenshareStatePath
        watchChanges: true
        onFileChanged: this.reload()
        onLoaded: {
            indicator.activelyScreenSharing = !stateFile.text().trim().toLowerCase().includes("none");
        }
    }

    MaterialSymbol {
        id: iconIndicator
        z: 1
        text: "cast"
        anchors.centerIn: parent
        color: Appearance.colors.colOnErrorContainer
        iconSize: Appearance.font.pixelSize.huge
    }

    StyledPopup {
        hoverTarget: indicator
        contentItem: HeroCard {
            compactMode: true
            anchors.centerIn: parent
            icon: "cast_connected"

            title: stateFile.text().trim()
            subtitle: Translation.tr("is using your screen")

            pillText: Translation.tr("Sharing..")
            pillIcon: "screen_share"
        }
    }
}
