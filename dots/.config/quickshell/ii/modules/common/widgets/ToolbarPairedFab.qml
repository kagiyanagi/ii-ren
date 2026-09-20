pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common

Item {
    id: root

    // AbstractButton.clicked carries no arguments, so the event this used to
    // declare and forward was always undefined. No caller read it.
    signal clicked
    property alias iconText: fabWidget.iconText
    property alias baseSize: fabWidget.baseSize
    default property alias fabData: fabWidget.data
    property bool enableShadow: true

    // No anchors here. Half the callers put this in a RowLayout, which sets x
    // and y itself -- Qt calls anchoring a layout's child undefined behavior and
    // only says so at runtime. Callers inside a plain Row that need centring
    // still set anchors.verticalCenter themselves; inside a layout it is
    // Layout.alignment, which now actually reaches the item.
    implicitWidth: fabWidget.implicitWidth
    implicitHeight: fabWidget.implicitHeight
    Loader {
        active: root.enableShadow
        anchors.fill: parent
        // The shadow's own anchors.fill targets fabWidget, which is a sibling of
        // this Loader and therefore neither parent nor sibling of the item the
        // Loader builds -- Qt refuses that anchor out loud. The Loader already
        // sizes it, so drop the anchor and keep the positioning out here.
        sourceComponent: StyledRectangularShadow {
            target: fabWidget
            anchors.fill: undefined
            radius: fabWidget.buttonRadius
        }
    }
    FloatingActionButton {
        id: fabWidget
        onClicked: root.clicked()
        baseSize: 48
        colBackground: Appearance.colors.colTertiaryContainer
        colBackgroundHover: Appearance.colors.colTertiaryContainerHover
        colRipple: Appearance.colors.colTertiaryContainerActive
        colOnBackground: Appearance.colors.colOnTertiaryContainer
        colStateLayer: Appearance.colors.colOnTertiaryContainer
    }
}
