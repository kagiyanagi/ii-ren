import qs.services
import QtQuick

/**
 * Brings its row into view and flashes it when settings search opens it.
 *
 * The row is this item's parent. It claims SearchRegistry.target when its label
 * matches and so do the section and subsection it sits in: "Enable" is a row
 * in five sections of one page. It checks when the target is set and when it
 * is created, since a result on another page or a sub-page is set before its
 * row exists. A fold the row is in opens; the page scrolls once the layout has
 * placed the row, which is the next frame's polish, not the next event.
 *
 * A page can still be filling in when its row is revealed (the Cursor page
 * lists cursor packs it has just scanned), which pushes the row back out of
 * view. So the row stays followed while it flashes, until the user moves the
 * page themselves.
 */
Item {
    id: handler
    property string searchString
    // The row's HighlightOverlay, which the flash plays on.
    property Item flash: null

    property Flickable page: null
    property bool revealing: false
    property bool following: false
    property bool flashPending: false

    function tryClaim() {
        const t = SearchRegistry.target;
        if (!t || !handler.parent || handler.searchString.toLowerCase() !== t.label.toLowerCase())
            return;
        let section = "";
        let subsection = "";
        for (let p = handler.parent.parent; p; p = p.parent) {
            if (p.searchScope === "subsection" && !section && !subsection)
                subsection = p.title;
            else if (p.searchScope === "section" && !section)
                section = p.title;
        }
        // Empty is "the index could not say", from a row declared in an inline
        // component, not "top level".
        if ((t.section && t.section !== section) || (t.subsection && t.subsection !== subsection))
            return;
        SearchRegistry.target = null;

        for (let p = handler.parent; p; p = p.parent)
            if (p.collapsible === true && p.expanded === false)
                p.expanded = true;
        handler.page = null;
        for (let p = handler.parent.parent; p && !handler.page; p = p.parent)
            if (p.contentY !== undefined && p.contentHeight !== undefined)
                handler.page = p;
        handler.flashPending = true;
        handler.following = handler.page !== null && handler.flash !== null;
        handler.requestReveal();
    }

    function requestReveal() {
        handler.revealing = true;
        handler.Window.window?.update();
    }

    function reveal() {
        const row = handler.parent;
        const page = handler.page;
        if (page && row) {
            const y = page.contentItem.mapFromItem(row, 0, 0).y;
            // Centred if it fits, its top at the top if it does not (a section).
            const want = row.height < page.height ? y - (page.height - row.height) / 2 : y;
            page.contentY = Math.max(0, Math.min(want, page.contentHeight - page.height));
        }
        if (handler.flashPending) {
            handler.flashPending = false;
            handler.flash?.startAnimation();
        }
    }

    Component.onCompleted: tryClaim()

    Connections {
        target: SearchRegistry
        function onTargetChanged() {
            handler.tryClaim();
        }
    }

    // afterAnimating is the GUI thread's, and comes after the frame's polish,
    // which is when the layouts give the row its final y.
    Connections {
        target: handler.revealing ? (handler.Window.window ?? null) : null
        function onAfterAnimating() {
            handler.revealing = false;
            handler.reveal();
        }
    }

    Connections {
        target: handler.following ? handler.page : null
        function onContentHeightChanged() {
            handler.requestReveal();
        }
        function onMovementStarted() {
            handler.following = false;
        }
    }

    Connections {
        target: handler.following ? handler.flash : null
        function onRunningChanged() {
            if (!handler.flash.running && !handler.flashPending)
                handler.following = false;
        }
    }
}
