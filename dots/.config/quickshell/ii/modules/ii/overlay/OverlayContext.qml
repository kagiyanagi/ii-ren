pragma Singleton
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import QtQuick

Singleton {
    id: root

    signal requestCenter(string identifier)

    /** Emitted after summon() has the widget on screen, for it to take focus. */
    signal summoned(string identifier)

    /** The label a widget shows when it declares none: `fpsLimiter` -> "Fps Limiter".
     *  Shared so the taskbar's icon-only button and the card's title bar cannot drift. */
    function titleFor(identifier: string): string {
        return identifier.replace(/([A-Z])/g, " $1").replace(/^./, c => c.toUpperCase());
    }

    /** Open the overlay straight onto one widget, adding it if it was switched off. */
    function summon(identifier: string): void {
        if (!Persistent.states.overlay.open.includes(identifier)) {
            Persistent.states.overlay.open.push(identifier);
        }
        GlobalStates.overlayOpen = true;
        root.summoned(identifier);
    }

    readonly property list<var> availableWidgets: [
        { identifier: "assist", materialSymbol: "smart_toy" },
        { identifier: "crosshair", materialSymbol: "point_scan" },
        { identifier: "fpsLimiter", materialSymbol: "animation" },
        { identifier: "floatingImage", materialSymbol: "imagesmode" },
        { identifier: "recorder", materialSymbol: "screen_record" },
        { identifier: "media", materialSymbol: "music_note" },
        { identifier: "resources", materialSymbol: "browse_activity" },
        { identifier: "notes", materialSymbol: "note_stack" },
        { identifier: "volumeMixer", materialSymbol: "volume_up" },
    ]

    property list<var> extensionWidgets: []

    /**
     * Mapping, not intent. The surface has to outlive `GlobalStates.overlayOpen` or there
     * is nothing left to play the exit on, so only the exit reaching 0 clears this -- see
     * `Overlay.qml`, which is what reads it.
     */
    property bool rendered: false

    /**
     * 0 dismissed, 1 open. Two of them because a scale and an opacity may not share a
     * spec (DESIGN.md 3): `openedProgress` rides the spatial enter and overshoots past 1,
     * `shownProgress` rides an effects spec and never does. Everything transient in the
     * overlay reads one of these rather than animating on its own.
     */
    property real openedProgress: 0
    property real shownProgress: 0
    property AnimSpec openSpec: Appearance.animation.elementMoveEnter
    property AnimSpec showSpec: Appearance.animation.elementMoveFast

    Behavior on openedProgress {
        NumberAnimation {
            duration: root.openSpec.duration
            easing.type: root.openSpec.type
            easing.bezierCurve: root.openSpec.bezierCurve
        }
    }
    Behavior on shownProgress {
        NumberAnimation {
            duration: root.showSpec.duration
            easing.type: root.showSpec.type
            easing.bezierCurve: root.showSpec.bezierCurve
        }
    }

    onShownProgressChanged: {
        // The opacity is what makes the surface invisible, so it is what decides the
        // surface is done. Re-opening mid-exit keeps the window and restarts from here.
        if (root.shownProgress === 0 && !GlobalStates.overlayOpen)
            root.rendered = false;
    }

    Connections {
        target: GlobalStates
        function onOverlayOpenChanged(): void {
            if (GlobalStates.overlayOpen) {
                root.rendered = true;
                root.openSpec = Appearance.animation.elementMoveEnter;
                root.showSpec = Appearance.animation.elementMoveFast;
                root.openedProgress = 1;
                root.shownProgress = 1;
                return;
            }
            const wasShowing = root.shownProgress > 0;
            root.openSpec = Appearance.animation.elementMoveExit;
            root.showSpec = Appearance.animation.elementMoveExit;
            root.openedProgress = 0;
            root.shownProgress = 0;
            if (!wasShowing) root.rendered = false; // nothing on screen to play an exit on
        }
    }

    /**
     * Derived, never reported. The widgets that would report themselves live inside the
     * window this decides to open, so self-registration could not work in either
     * direction: a pin never survived a shell restart (nothing was alive to say it was
     * pinned), and a pinned widget closed from its own X left the full-screen surface
     * mapped for the rest of the session with a destroyed Item still in its input mask.
     * An extension widget's pin is merged into `extensionWidgets` by
     * `ExtensionManager.getContributionPoint`, which re-runs whenever one is saved.
     */
    readonly property list<string> pinnedWidgetIdentifiers: Persistent.states.overlay.open.filter(identifier =>
        (Persistent.states.overlay[identifier] ?? root.extensionWidgets.find(w => w.identifier === identifier))?.pinned ?? false)

    readonly property bool hasPinnedWidgets: root.pinnedWidgetIdentifiers.length > 0

    /**
     * The input mask needs the live Item, not a name, so this one stays a registration --
     * and every caller unregisters on destruction, because a destroyed Item left in here
     * is a Region over nothing.
     */
    property list<var> clickableWidgets: []

    function refreshExtensionWidgets() {
        root.extensionWidgets = ExtensionManager.getContributionPoint("overlayWidgets")
    }

    function registerClickableWidget(widget: var, clickable = true) {
        const rest = root.clickableWidgets.filter(w => w !== widget);
        root.clickableWidgets = clickable ? [...rest, widget] : rest;
    }

    Connections {
        target: ExtensionManager
        function onRefreshExtensions() {
            root.refreshExtensionWidgets()
        }
    }

    Component.onCompleted: {
        if (ExtensionManager.ready) {
            root.refreshExtensionWidgets()
        } else {
            let checkReady = () => {
                if (ExtensionManager.ready) {
                    root.refreshExtensionWidgets()
                } else {
                    Qt.callLater(checkReady)
                }
            }
            Qt.callLater(checkReady)
        }
    }
}
