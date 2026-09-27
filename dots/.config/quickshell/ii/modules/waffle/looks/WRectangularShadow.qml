pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks

StyledRectangularShadow {
    blur: 10
    spread: 2
    offset: Qt.vector2d(0.0, 4)
    color: Looks.colors.shadow
}
