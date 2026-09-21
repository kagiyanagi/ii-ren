import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets

Item {
    id: root
    property string appId: ""
    property bool isRunning: true

    readonly property bool monochrome: Config.options.dock.monochromeIcons
    readonly property bool dimmed: !isRunning && Config.options.dock.dimInactiveIcons
    property real iconOpacity: dimmed ? 0.55 : 1.0

    // Every dock icon is a delegate, so an effect here costs a framebuffer per
    // app on the strip (DESIGN.md 8) -- and check-effect-budget.py cannot see
    // it, because its delegates live in their own files rather than inside a
    // Repeater block it can read. This used to be a Desaturate *and* a
    // ColorOverlay, both instantiated whether or not they drew anything, with
    // monochrome on by default: two framebuffers times however many apps are
    // pinned. One MultiEffect does both, as a layer effect so there is no
    // second ShaderEffectSource, and only while there is something to do.
    // tools/check-dock.py is what keeps it at one.
    IconImage {
        id: baseIcon
        anchors.fill: parent
        source: Quickshell.iconPath(TaskbarApps.getCachedIcon(root.appId), "image-missing")
        opacity: root.iconOpacity

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        layer.enabled: root.monochrome || root.dimmed
        layer.effect: MultiEffect {
            // Desaturate's old 0.8, as MultiEffect states it.
            saturation: -0.8
            // The tint was a ColorOverlay at one tenth alpha; colorization is
            // the same weight against the icon's own luminance.
            colorization: root.monochrome ? 0.1 : 0
            colorizationColor: Appearance.colors.colPrimary
        }
    }
}
