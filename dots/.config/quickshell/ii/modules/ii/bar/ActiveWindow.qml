import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root
    property bool vertical: false
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    property string activeWindowAddress: `0x${activeWindow?.HyprlandToplevel?.address}`
    property bool focusingThisMonitor: HyprlandData.activeWorkspace?.monitor == monitor?.name
    property var biggestWindow: HyprlandData.biggestWindowForWorkspace(HyprlandData.monitors[root.monitor?.id]?.activeWorkspace.id)

    readonly property bool isFixedSize: Config.options.bar.activeWindow.fixedSize

    readonly property int maxSize: 350
    readonly property int fixedSize: root.vertical ? 150 : 225

    // Focused here: the active window. Otherwise the biggest on this monitor's
    // workspace, or the desktop when it has none.
    readonly property bool showsActive: !!(root.focusingThisMonitor && root.activeWindow?.activated && root.biggestWindow)

    property string appClassText: root.showsActive ? (root.activeWindow?.appId ?? "") : (root.biggestWindow?.class) ?? Translation.tr("Desktop")
    property string appTitleText: root.showsActive ? (root.activeWindow?.title ?? "") : (root.biggestWindow?.title) ?? `${Translation.tr("Workspace")} ${monitor?.activeWorkspace?.id ?? 1}`
    
    implicitHeight: isFixedSize ? fixedSize : (root.vertical ? Math.max(classText.implicitWidth, titleText.implicitWidth) + 20 : colLayout.implicitHeight)
    implicitWidth: isFixedSize ? fixedSize : Math.min(Math.max(classText.implicitWidth, titleText.implicitWidth) + 20, maxSize)
    clip: true

    Behavior on implicitWidth {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }
    Behavior on implicitHeight {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    ColumnLayout {
        visible: true
        id: colLayout

        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: -4

        width: root.vertical ? implicitWidth : root.width
        height: root.vertical ? root.height : implicitHeight

        StyledText {
            id: classText
            Layout.leftMargin: 6
            visible: !root.vertical
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            text: root.appClassText
        }

        StyledText {
            id: titleText
            Layout.leftMargin: root.vertical ? 0 : 6
            Layout.fillWidth: true
            // Third-rank text: the workspaces beside it and the clock own
            // colOnLayer0, so the title sits one step down the role ladder (6.1)
            // and cannot compete with them.
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
            elide: Text.ElideRight
            rotation: root.vertical ? 90 : 0
            text: root.vertical ? root.appClassText : root.appTitleText
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
    }

    ActiveWindowPopup {
        hoverTarget: mouseArea
        appClass: root.appClassText
        appTitle: root.appTitleText
        address: root.showsActive ? root.activeWindowAddress : (root.biggestWindow?.address ?? "")
        monitorName: root.monitor?.name ?? ""
        workspaceId: root.monitor?.activeWorkspace?.id ?? 1
    }
}