import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Image {
    asynchronous: true
    retainWhileLoading: true
    visible: opacity > 0
    opacity: (status === Image.Ready) ? 1 : 0
    Behavior on opacity {
        // elementMoveEnter is a spatial spec and its curve overshoots past 1, which
        // on opacity clips into a flash (DESIGN.md 2.1, 10.6).
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    property list<string> fallbacks: []
    property int currentFallbackIndex: 0

    onStatusChanged: {
        if (status === Image.Error && currentFallbackIndex < fallbacks.length) {
            source = fallbacks[currentFallbackIndex];
            currentFallbackIndex += 1;
        }
    }

    sourceSize: {
        const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
        return Qt.size(width * dpr, height * dpr);
    }
}
