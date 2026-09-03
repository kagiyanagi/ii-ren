pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "nagasaki_text"

    readonly property real configSize: Config.options.background.widgets.nagasaki_text.size ?? 200
    // Drives the glyphs, so it must not read back the box the glyphs size:
    // the label used to take 0.8 of the widget's height, and the widget's
    // height is now measured from the label.
    readonly property real glyphSize: configSize * 0.8

    // The box is the digits' ink, not the square the size slider names. The
    // label is a line box — taller than the digits by the font's descent, and
    // as wide as its widest digits rather than the time on screen — and the
    // square around it was leaving a dead band on all four sides.
    implicitWidth: Math.max(1, refMetrics.tightBoundingRect.width)
    implicitHeight: Math.max(1, refMetrics.tightBoundingRect.height)

    // Fixed reference rather than the live time, so the box does not resize
    // every minute. "0000" is the widest four digits in this face.
    TextMetrics {
        id: refMetrics
        font: timeLabel.font
        text: "0000"
    }

    FontLoader {
        id: nagasakiFont
        source: "file://" + Directories.assetsPath + "/fonts/nagasaki.ttf"
    }

    readonly property string hour: DateTime.time.split(":")[0].padStart(2, "0")
    readonly property string minute: DateTime.time.split(":")[1].split(" ")[0].padStart(2, "0")
    readonly property string timeText: hour + minute

    readonly property color textColor: WidgetColorScheme.cardBgColor

    Text {
        id: timeLabel
        // Line box shifted so the digits' ink lands on the widget's box, with
        // the time centred across it so a narrow hour does not drift.
        x: 0
        y: refMetrics.boundingRect.y - refMetrics.tightBoundingRect.y
        width: root.width
        text: root.timeText
        font.family: nagasakiFont.name
        font.pixelSize: root.glyphSize
        color: root.textColor
        horizontalAlignment: Text.AlignHCenter
    }

    StyledDropShadow {
        target: timeLabel
        visible: Config.options.background.widgets.enableShadows ?? false
    }
}
