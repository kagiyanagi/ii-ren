import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar as Bar

Item { // Bar content region
    id: root

    property var screen: root.QsWindow.window?.screen
    // Computed by VerticalBar.qml, which is where monitorIndex actually lives.
    required property bool showBarBackground

    ////// Definning places of center modules //////
    property var fullModel: Config.options?.bar?.layouts?.center

    property int centerIdx: (fullModel || []).findIndex(item => item.centered)

    property var leftList: centerIdx === -1 ? [] : fullModel.slice(0, centerIdx)
    property var centerList: centerIdx === -1 ? fullModel : [fullModel[centerIdx]]
    property var rightList: centerIdx === -1 ? [] : fullModel.slice(centerIdx + 1)

    // Background shadow
    Loader {
        active: root.showBarBackground && Config.options.bar.cornerStyle === 1 && Config.options.bar.floatStyleShadow
        anchors.fill: barBackground
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: barBackground
        }
    }
    // Background
    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: Config.options.bar.cornerStyle === 1 ? (Appearance.sizes.hyprlandGapsOut) : 0 // idk why but +1 is needed
        }
        z: -10 // making sure its behind everything
        color: root.showBarBackground ? Appearance.colors.colLayer0 : "transparent"
        radius: Config.options.bar.cornerStyle === 1 ? (Config.options.bar.cornerRadius ?? Appearance.rounding.windowRounding) : 0
        border.width: Config.options.bar.cornerStyle === 1 ? 1 : 0
        border.color: root.showBarBackground ? Appearance.colors.colLayer0Border : "transparent"
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    FocusedScrollMouseArea { // Top section | scroll to change brightness
        id: barTopSectionMouseArea

        anchors {
            top: parent.top
            bottom: middleSection.top
            left: parent.left
            right: parent.right
        }

        onScrollDown: Brightness.decreaseBrightness()
        onScrollUp: Brightness.increaseBrightness()
        onMovedAway: GlobalStates.osdBrightnessOpen = false
        onPressed: event => {
            if (event.button === Qt.LeftButton)
                GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }

    }

    Item {
        id: topStopper
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            topMargin: Math.ceil(Appearance.rounding.screenRounding / 2.5)
        }
        height: 1
    }

    ColumnLayout { // Top section
        id: topSection
        anchors {
            top: topStopper.bottom
            horizontalCenter: parent.horizontalCenter
        }
        spacing: 4

        Repeater {
            id: leftRepeater
            model: Config.options.bar.layouts.left
            delegate: Bar.BarComponent {
                vertical: true
                list: Config.options.bar.layouts.left
                barSection: 0
            }
        }
    }

    Item {
        id: middleSection
        anchors {
            horizontalCenter: parent.horizontalCenter
            verticalCenter: parent.verticalCenter
        }

        ColumnLayout {
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: centerCenter.top
                bottomMargin: 4
            }
            spacing: 4
            Repeater {
                id: middleLeftRepeater
                model: root.leftList
                delegate: Bar.BarComponent {
                    vertical: true
                    list: Config.options.bar.layouts.center
                    barSection: 1
                    originalIndex: index
                }
            }
        }

        ColumnLayout { //center
            id: centerCenter
            anchors {
                horizontalCenter: parent.horizontalCenter
                verticalCenter: parent.verticalCenter
            }
            spacing: 4
            Repeater {
                model: root.centerList
                delegate: Bar.BarComponent {
                    vertical: true
                    list: Config.options.bar.layouts.center
                    barSection: 1
                    originalIndex: root.leftList.length + index
                }
            }
        }

        ColumnLayout {
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: centerCenter.bottom
                topMargin: 4
            }
            spacing: 4
            Repeater {
                id: middleRightRepeater
                model: root.rightList
                delegate: Bar.BarComponent {
                    vertical: true
                    list: Config.options.bar.layouts.center
                    barSection: 1
                    originalIndex: root.leftList.length + root.centerList.length + index
                }
            }
        }

    }

    ColumnLayout { // Bottom section
        id: bottomSection
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: bottomStopper.top
        }
        spacing: 4

        Repeater {
            id: rightRepeater
            model: Config.options.bar.layouts.right
            delegate: Bar.BarComponent {
                vertical: true
                list: Config.options.bar.layouts.right
                barSection: 2
            }
        }
    }

    Item {
        id: bottomStopper
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            bottomMargin: Math.ceil(Appearance.rounding.screenRounding / 2.5)
        }
        height: 1
    }

    FocusedScrollMouseArea { // Bottom section | scroll to change volume
        id: barBottomSectionMouseArea

        z: -1
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            top: middleSection.bottom
        }

        onScrollDown: Audio.decrementVolume();
        onScrollUp: Audio.incrementVolume();
        onMovedAway: GlobalStates.osdVolumeOpen = false;
        onPressed: event => {
            if (event.button === Qt.LeftButton) {
                GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            }
        }
    }
}
