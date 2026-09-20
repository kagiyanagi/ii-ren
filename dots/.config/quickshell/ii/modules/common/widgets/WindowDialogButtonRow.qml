import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

RowLayout {
    id: root
    spacing: 4

    // The confirming action sits at the dialog's right edge (DESIGN.md 9), which
    // it only can if the row spans the dialog: every caller already puts a
    // filler Item beside its buttons, and without this the filler had no width
    // to take and the whole group sat at the left.
    Layout.fillWidth: true
}
