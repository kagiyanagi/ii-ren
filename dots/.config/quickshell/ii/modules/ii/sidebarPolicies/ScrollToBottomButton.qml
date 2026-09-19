import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root
    required property StyledListView target

    anchors {
        bottom: parent.bottom
        horizontalCenter: parent.horizontalCenter
        bottomMargin: 10
    }

    /*
     * A list that follows its own end already knows whether the reader has left
     * it. Anywhere else, `atYEnd` has to answer -- and it goes false the instant
     * a streamed token grows the content, so it is given a beat to settle first:
     * a gap that closes on the next frame is the view catching up to new
     * content, not someone scrolling back to re-read.
     */
    readonly property bool away: target.followsEnd ? !target.followingEnd : !target.atYEnd
    property bool shown: false

    onAwayChanged: {
        if (!root.away) {
            settleTimer.stop();
            root.shown = false;
        } else if (!settleTimer.running) {
            settleTimer.restart();
        }
    }

    Timer {
        id: settleTimer
        interval: Appearance.animation.elementMoveFast.duration
        onTriggered: root.shown = root.away
    }

    opacity: root.shown ? 1 : 0
    scale: root.shown ? 1 : 0.7
    visible: opacity > 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    implicitWidth: contentItem.implicitWidth + 8 * 2
    implicitHeight: contentItem.implicitHeight + 4 * 2

    colBackground: Appearance.colors.colSecondary
    colBackgroundHover: Appearance.colors.colSecondaryHover
    colRipple: Appearance.colors.colSecondaryActive
    buttonRadius: Appearance.rounding.verysmall

    downAction: () => {
        target.jumpToEnd();
    }

    contentItem: Row {
        id: contentItem
        spacing: 4
        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: "arrow_downward"
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSecondary
            verticalAlignment: Text.AlignVCenter
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: Translation.tr("Scroll to Bottom")
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colOnSecondary
            verticalAlignment: Text.AlignVCenter
        }
    }
}
