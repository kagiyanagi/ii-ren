pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks

AcrylicButton {
    id: root

    Layout.fillHeight: true
    topInset: 4
    bottomInset: 4
    leftInset: 0
    rightInset: 0
    horizontalPadding: 8

    colBackground: ColorUtils.transparentize(Looks.colors.bg1)
}
