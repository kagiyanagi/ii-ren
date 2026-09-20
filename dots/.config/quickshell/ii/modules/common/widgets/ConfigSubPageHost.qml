import QtQuick
import Quickshell
import qs.modules.common

/**
 * Slide-in sub-page overlay shared by settings pages that host widget config
 * sub-pages. Fill the page root with it (z above the main content) and bind
 * the main content's opacity to `slideProgress` for the cross-fade.
 * Sub-pages are expected to expose `showBackButton` and a `goBack` signal
 * (ContentPage does).
 */
Item {
    id: host

    // URL of the open sub-page; empty = closed. Resolve relative paths at the
    // call site (Qt.resolvedUrl) so they stay relative to the caller's file.
    property url activeSubPage: ""
    readonly property bool isOpen: activeSubPage.toString() !== ""
    signal navigationChanged()
    // The Settings window uses this path to keep nested configuration pages
    // in the local mouse-back history (for example Drive -> Advanced Drive).
    readonly property var navigationPath: {
        const first = activeSubPage.toString();
        if (first === "")
            return [];

        const path = [first];
        const nestedHost = findNestedNavigationHost(subPageLoader.item);
        if (nestedHost && nestedHost.navigationPath.length > 0)
            return path.concat(nestedHost.navigationPath);
        return path;
    }
    // 1 when closed, 0 when fully open — bind the main page's opacity to this
    readonly property real slideProgress: width > 0 ? slider.x / width : 1

    function open(url) {
        activeSubPage = url;
    }

    function close() {
        activeSubPage = "";
    }

    function requestBack() {
        const win = host.QsWindow.window;
        if (win && win.navigateBack !== undefined && win.navigateBack())
            return;
        host.close();
    }

    function findNestedNavigationHost(node) {
        if (!node)
            return null;
        if (node.navigationPath !== undefined && node !== host)
            return node;

        if (node.item) {
            const itemHost = findNestedNavigationHost(node.item);
            if (itemHost)
                return itemHost;
        }

        const children = node.children || [];
        for (let i = 0; i < children.length; ++i) {
            const childHost = findNestedNavigationHost(children[i]);
            if (childHost)
                return childHost;
        }
        return null;
    }

    function restoreNavigationPath(path) {
        const normalizedPath = Array.isArray(path) ? path : [];
        activeSubPage = normalizedPath.length > 0 ? normalizedPath[0] : "";

        // The Loader may need one event-loop turn to create the page before
        // its own ConfigSubPageHost can receive the remaining path.
        Qt.callLater(function() {
            const nestedHost = findNestedNavigationHost(subPageLoader.item);
            if (nestedHost && nestedHost.restoreNavigationPath)
                nestedHost.restoreNavigationPath(normalizedPath.slice(1));
        });
    }

    // Keep the host interactive while the close animation is leaving the
    // screen. Without this, the page underneath becomes hover/clickable for
    // the last frames of every sub-page transition.
    enabled: isOpen || slider.overlayActive
    onIsOpenChanged: {
        if (isOpen)
            slider.overlayActive = true;

    }
    onActiveSubPageChanged: host.navigationChanged()

    // Cover the entire host, including the area left behind while the page
    // slides closed. The loaded page is declared after this shield and stays
    // above it, so its controls remain usable while the parent page cannot
    // receive hover/click events.
    MouseArea {
        anchors.fill: parent
        enabled: host.enabled
        visible: host.enabled
        hoverEnabled: true
        // Leave the mouse side button for SettingsWindow's local history
        // handler. Normal buttons are still blocked from reaching the page
        // underneath while the sub-page is open or closing.
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: event => event.accepted = true
    }

    Item {
        id: slider
        z: 1

        // overlayActive stays true during the close animation (until x reaches width)
        property bool overlayActive: host.isOpen

        width: parent.width
        height: parent.height
        y: 0
        onXChanged: {
            if (!host.isOpen && x >= slider.width - 1)
                overlayActive = false;

        }
        // Entering is the default spatial spec and decelerates; leaving is the
        // fast effects one, monotone and a quarter as long, because by then the
        // user has already decided (2.5). Monotone also matters here: the old
        // spatial spec overshot past `width` on the way out, and overlayActive
        // is released at `x >= width - 1`.
        //
        // The spec is assigned from inside the x binding, not from a binding of
        // its own. A Behavior bakes duration and curve at the instant the write
        // happens, and a sibling binding on isOpen is not necessarily current by
        // then, so the exit would run on the enter's curve. Revealer and
        // PagePlaceholder are the worked examples; DESIGN.md 2.9.
        property AnimSpec slideSpec: Appearance.animation.elementMove

        // Open: x=0. Closed: x=width (off-screen right).
        x: {
            slider.slideSpec = host.isOpen ? Appearance.animation.elementMove : Appearance.animation.elementMoveExit;
            return host.isOpen ? 0 : slider.width;
        }

        Loader {
            id: subPageLoader

            anchors.fill: parent
            source: host.activeSubPage
            active: slider.overlayActive
            asynchronous: true
            onStatusChanged: { if (status === Loader.Error) console.error("LOADER_ERROR: " + source); }
            onLoaded: {
                if (item.hasOwnProperty("showBackButton"))
                    item.showBackButton = true;

                item.goBack.connect(host.requestBack);
            }
        }

        Behavior on x {
            NumberAnimation {
                alwaysRunToEnd: false
                duration: slider.slideSpec.duration
                easing.type: slider.slideSpec.type
                easing.bezierCurve: slider.slideSpec.bezierCurve
            }

        }

    }

}
