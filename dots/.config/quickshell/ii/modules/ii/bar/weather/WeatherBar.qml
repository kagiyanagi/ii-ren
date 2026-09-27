pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Quickshell
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool vertical: false

    // Weather.data ships a complete placeholder reading - 0 degrees, city
    // "City", sunrise at 00:00 - so "nothing has arrived yet" and "it is
    // freezing at midnight" render identically. wmoCode starts at -1 and is
    // the one field refineData always overwrites, so it is what says whether
    // any of the rest is a measurement.
    readonly property bool hasReading: (Weather.data?.wmoCode ?? -1) >= 0

    // A bar item is a handle that opens a popup, so it needs a real hit area
    // even when the glyph inside it is small (DESIGN.md 3.4: 32px floor on a
    // pointer-driven shell). The padding is on the 4dp grid; 25 was not.
    implicitWidth: Math.max(32, rowLayout.implicitWidth + 20)
    implicitHeight: Math.max(32, rowLayout.implicitHeight + (root.vertical ? 20 : 12))

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    cursorShape: Qt.PointingHandCursor

    // The reading changes width under the pointer ("9°" to "-12°"), and so
    // does the strip around it.
    Behavior on implicitWidth {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    onPressed: mouse => {
        if (mouse.button === Qt.RightButton) {
            Weather.getData();
            Quickshell.execDetached(["notify-send", Translation.tr("Weather"), Translation.tr("Refreshing (manually triggered)"), "-a", "Shell"]);
            mouse.accepted = false;
        }
    }

    // The state film, off the layer the bar itself paints (DESIGN.md 3.1, 6.1):
    // hover 0.08 and focus/pressed 0.10 are already mixed into colLayer0Hover /
    // colLayer0Active and stay right when bar transparency is on, which a
    // hand-mixed tint would not. A filled item takes the film rather than a
    // scale (3.3) - a growing rectangle in a status strip reads as a layout
    // glitch. The item is never disabled, so there is no 0.4 case.
    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.full
        color: (root.containsPress || root.activeFocus) ? Appearance.colors.colLayer0Active : root.containsMouse ? Appearance.colors.colLayer0Hover : ColorUtils.transparentize(Appearance.colors.colLayer0Hover, 1)

        // Fading to a fully transparent *colLayer0Hover* rather than to
        // "transparent" keeps the hue through the fade; "transparent" is
        // transparent black and greys the film out on a light wallpaper.
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    GridLayout {
        id: rowLayout
        anchors.centerIn: parent

        columns: root.vertical ? 1 : 2
        rows: root.vertical ? 2 : 1

        Loader {
            id: iconLoader
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            sourceComponent: (Config.options.bar.weather.dynamicIcon ?? true) ? dynamicIconComp : symbolIconComp
        }

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
            text: root.hasReading ? Weather.data.temp : "--°"
            Layout.alignment: root.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
        }
    }

    Component {
        id: dynamicIconComp

        Image {
            width: 20
            height: 20
            source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, Weather.isNight)
            sourceSize: Qt.size(40, 40)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
    }

    Component {
        id: symbolIconComp

        MaterialSymbol {
            fill: 0
            text: WeatherIcons.getMaterialSymbol(Weather.data?.wCode ?? 113)
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
        }
    }

    WeatherPopup {
        hoverTarget: root
    }
}
