pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks

StyledIndeterminateProgressBar {
    id: progressBar
    implicitHeight: 4
    valueBarHeight: 4
    highlightColor: Looks.colors.accent
    trackColor: Looks.colors.controlBg
}
