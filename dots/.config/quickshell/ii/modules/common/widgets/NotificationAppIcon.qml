pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

MaterialShape { // App icon
    id: root
    property var appIcon: ""
    property var summary: ""
    property var urgency: NotificationUrgency.Normal
    // The service stores urgency as the enum's decimal string; Number() reads
    // that and the raw enum a caller may hand over.
    property bool isUrgent: Number(root.urgency) === NotificationUrgency.Critical
    property var image: ""
    property real materialIconScale: 0.57
    property real appIconScale: 0.8
    property real smallAppIconScale: 0.49
    property real materialIconSize: root.implicitSize * root.materialIconScale
    property real appIconSize: root.implicitSize * root.appIconScale
    property real smallAppIconSize: root.implicitSize * root.smallAppIconScale

    implicitSize: 38
    property list<var> urgentShapes: [
        MaterialShape.Shape.VerySunny,
        MaterialShape.Shape.SoftBurst,
    ]
    // Rolled once, not inside the `shape` binding: there it re-rolled on every
    // re-evaluation and ShapeCanvas morphed the icon between the two shapes each
    // time something unrelated changed.
    readonly property int urgentShapeIndex: Math.floor(Math.random() * root.urgentShapes.length)
    shape: root.isUrgent ? root.urgentShapes[root.urgentShapeIndex] : MaterialShape.Shape.Circle

    color: root.isUrgent ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
    Loader {
        id: materialSymbolLoader
        active: root.appIcon == "" && root.image == ""
        anchors.fill: parent
        sourceComponent: MaterialSymbol {
            text: {
                const defaultIcon = NotificationUtils.findSuitableMaterialSymbol("")
                const guessedIcon = NotificationUtils.findSuitableMaterialSymbol(root.summary)
                return (root.isUrgent && guessedIcon === defaultIcon) ? "priority_high" : guessedIcon
            }
            anchors.fill: parent
            color: root.isUrgent ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
            iconSize: root.materialIconSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
    Loader {
        id: appIconLoader
        active: root.image == "" && root.appIcon != ""
        anchors.centerIn: parent
        sourceComponent: IconImage {
            implicitSize: root.appIconSize
            asynchronous: true
            source: Quickshell.iconPath(root.appIcon, "image-missing")
        }
    }
    Loader {
        id: notifImageLoader
        active: root.image != ""
        anchors.fill: parent
        sourceComponent: Item {
            anchors.fill: parent
            StyledImage {
                id: notifImage
                anchors.fill: parent
                readonly property int size: parent.width

                source: root.image
                fillMode: Image.PreserveAspectCrop
                cache: false
                antialiasing: true
                asynchronous: true

                // design-ok: 8 says prefer a native radius to an OpacityMask, and
                // Image has none. Quickshell's ClippingRectangle is the obvious
                // swap and is worse -- it is a Rectangle layer plus a
                // ShaderEffectSource plus a ShaderEffect, two FBOs where this is
                // one. Only a notification that carries an image pays it.
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: notifImage.size
                        height: notifImage.size
                        radius: Appearance.rounding.full
                    }
                }
            }
            Loader {
                id: notifImageAppIconLoader
                active: root.appIcon != ""
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                sourceComponent: IconImage {
                    implicitSize: root.smallAppIconSize
                    asynchronous: true
                    source: Quickshell.iconPath(root.appIcon, "image-missing")
                }
            }
        }
    }
}
