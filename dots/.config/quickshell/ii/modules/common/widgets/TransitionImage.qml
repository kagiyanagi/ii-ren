import QtQuick
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    required property string imageSource

    // "random" rolls a new style on every wallpaper change, in fadeTo().
    readonly property string configuredType: Config.options.background.transitionType ?? "radial"
    property string randomType: "radial"
    property string transitionType: configuredType === "random" ? randomType : configuredType

    // design-ok: full-screen wallpaper crossing, screen-sized per DESIGN.md 2.4 --
    // no Appearance spec covers this scale, so it is a config knob instead of a
    // token. Radial keeps the 10% it has always had over the others: its circle
    // crosses the diagonal while the rest cross an edge.
    property int animationDuration: Math.round((Config.options.background.transitionDuration ?? 2000) * (transitionType === "radial" ? 1.1 : 1))
    property var fillMode: Image.PreserveAspectCrop
    property bool animated: Config.options.background.animateWallpaperChanges

    property var sourceSize: Qt.size(0, 0)
    property bool cache: false
    property bool antialiasing: true
    property bool asynchronous: true
    property bool smooth: true
    property bool mipmap: true

    property bool transitionActive: false
    property bool ready: false

    property bool imgAIsBack: true
    property Item backImg: imgAIsBack ? imgA : imgB
    property Item frontImg: imgAIsBack ? imgB : imgA

    property int status: (imgA.status === Image.Ready || imgB.status === Image.Ready) ? Image.Ready : frontImg.status

    Component.onCompleted: ready = true

    onImageSourceChanged: fadeTo(imageSource)

    property string currentWallpaper: ""

    function fadeTo(newSrc) {
        if (!newSrc || newSrc === currentWallpaper) return

        let hasWallpaper = (currentWallpaper !== "")

        if (root.animated && ready && root.width > 0 && root.height > 0 && hasWallpaper) {
            cleanupTransition()
            if (configuredType === "random") {
                const types = ["radial", "crossfade", "wipe", "diamond", "slash", "outer", "wave"]
                randomType = types[Math.floor(Math.random() * types.length)]
            }

            // Flip AT THE START so frontImg is ALWAYS the new image with z=1
            root.imgAIsBack = !root.imgAIsBack
            
            root.transitionActive = true
            frontImg.source = newSrc 
            currentWallpaper = newSrc
            
            let wait = effectLoader.item ? effectLoader.item.waitForReady !== false : true
            
            if (!wait || frontImg.status === Image.Ready) {
                startTransition()
            }
        } else {
            cleanupTransition()
            root.imgAIsBack       = !root.imgAIsBack 
            frontImg.source       = newSrc
            currentWallpaper      = newSrc
            root.transitionActive = false
        }
    }

    function startTransition() {
        if (effectLoader.item && typeof effectLoader.item.start === "function") {
            effectLoader.item.start()
        } else {
            cleanupTransition()
        }
    }

    function cleanupTransition() {
        root.transitionActive = false
        if (effectLoader.item && typeof effectLoader.item.cleanup === "function") {
            effectLoader.item.cleanup()
        }
    }

    Image {
        id: imgA
        anchors.fill: parent
        // Visible if backImg OR (if frontImg and no hideFront requested during transition)
        visible: root.imgAIsBack || (!root.transitionActive || !effectLoader.item || effectLoader.item.hideFront === false)
        layer.enabled: !visible && root.transitionActive 
        z:       root.imgAIsBack ? 0 : 1

        fillMode:     root.fillMode
        sourceSize:   root.sourceSize
        cache: root.cache; antialiasing: root.antialiasing
        asynchronous: root.asynchronous; smooth: root.smooth; mipmap: root.mipmap

        onStatusChanged: {
            let wait = effectLoader.item ? effectLoader.item.waitForReady !== false : true
            if (wait) {
                if (status === Image.Ready && root.transitionActive && !root.imgAIsBack) {
                    root.startTransition()
                } else if (status === Image.Error && root.transitionActive && !root.imgAIsBack) {
                    root.cleanupTransition()
                }
            }
        }
    }

    Image {
        id: imgB
        anchors.fill: parent
        visible: !root.imgAIsBack || (!root.transitionActive || !effectLoader.item || effectLoader.item.hideFront === false)
        layer.enabled: !visible && root.transitionActive
        z:       !root.imgAIsBack ? 0 : 1

        fillMode:     root.fillMode
        sourceSize:   root.sourceSize
        cache: root.cache; antialiasing: root.antialiasing
        asynchronous: root.asynchronous; smooth: root.smooth; mipmap: root.mipmap
        
        onStatusChanged: {
            let wait = effectLoader.item ? effectLoader.item.waitForReady !== false : true
            if (wait) {
                if (status === Image.Ready && root.transitionActive && root.imgAIsBack) {
                    root.startTransition()
                } else if (status === Image.Error && root.transitionActive && root.imgAIsBack) {
                    root.cleanupTransition()
                }
            }
        }
    }

    Loader {
        id: effectLoader
        anchors.fill: parent
        source: "transitions/" + (root.transitionType.charAt(0).toUpperCase() + root.transitionType.slice(1)) + ".qml"

        onLoaded: {
            item.frontImg = Qt.binding(function() { return root.frontImg })
            item.backImg = Qt.binding(function() { return root.backImg })
            item.duration = Qt.binding(function() { return root.animationDuration })
        }
        
        Connections {
            target: effectLoader.item ?? null
            function onFinished() {
                root.cleanupTransition()
            }
        }
    }
}