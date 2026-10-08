import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// A subsection header on its own. Inset to the icon column of the card rows
// below it (the card's 8 bleed + the row's 8 padding, less 6 for the glyph's
// side bearing as before), and held 8 off the run above, as a ContentSubsection
// header is; ContentSubsection zeroes both for the copy in its own header row.
StyledText {
    text: "Subsection"
    color: Appearance.colors.colSubtext
    Layout.leftMargin: 10
    Layout.topMargin: 8
}
