import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The label above a group of dialog rows. What used to separate those groups was
 * a hairline divider, which DESIGN.md 5.5 forbids; the replacement is whitespace
 * and a tonal card, so this carries the extra air above itself and reads as a
 * subtitle rather than a second title. For anything more structured
 * than a label, a dialog groups with ContentSubsection exactly like a settings
 * page does.
 */
StyledText {
    text: "Section"
    color: Appearance.colors.colSubtext
    wrapMode: Text.Wrap
    Layout.fillWidth: true
    // On top of the dialog column's own 16, so a new section opens with 24 of
    // whitespace -- the 12-16 gap 5.5 asks for, and then some, since it is doing
    // a divider's job.
    Layout.topMargin: 8
    font {
        family: Appearance.font.family.title
        pixelSize: Appearance.font.pixelSize.normal
        variableAxes: Appearance.font.variableAxes.title
    }
}
