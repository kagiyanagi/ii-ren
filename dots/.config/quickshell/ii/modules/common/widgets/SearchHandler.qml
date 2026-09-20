import qs.services
import QtQuick

/**
 * Scrolls its owner into view and flashes it when a settings search matches.
 *
 * `page`, `root` and `highlightOverlay` are not declared here -- they are
 * resolved out of the creation-context chain of whatever instantiated this, so
 * this only works where all three exist somewhere up that chain (the settings
 * pages declare `page`; the carded rows declare `root` and `highlightOverlay`).
 * A bare reference to an identifier the chain does not carry throws a
 * ReferenceError rather than evaluating to undefined, which is the same trap
 * ContentSection.Component.onCompleted hit -- hence the typeof guards. Failing
 * soft here means the row does not scroll into view; it used to mean a throw
 * inside a Qt.callLater, from a widget that had no idea which file it was in.
 */
Item {
    id: searchHandler
    readonly property string currentSearch: SearchRegistry.currentSearch
    property string searchString

    onCurrentSearchChanged: {
        if (SearchRegistry.currentSearch.toLowerCase() !== searchHandler.searchString.toLowerCase())
            return;
        const ownerPage = (typeof page !== 'undefined') ? page : null;
        const owner = (typeof root !== 'undefined') ? root : null;
        const flash = (typeof highlightOverlay !== 'undefined') ? highlightOverlay : null;
        SearchRegistry.currentSearch = "";
        if (!ownerPage || !owner)
            return;
        Qt.callLater(() => {
            const p = ownerPage.contentItem.mapFromItem(owner, 0, 0);
            const maxContentY = Math.max(0, ownerPage.contentHeight - ownerPage.height);
            ownerPage.contentY = Math.max(0, Math.min(p.y - 100, maxContentY));
            flash?.startAnimation();
        });
    }
}
