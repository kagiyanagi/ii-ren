pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import "settingsSearch.js" as Search

/**
 * Settings search. settings.qml hands its page list to index(); every page, and
 * every sub-page a page opens, is read as text and parsed (settingsSearch.js),
 * so a setting is searchable before its page has ever been opened and nothing
 * registers at runtime. query() ranks.
 *
 * Opening a result sets `target`; the SearchHandler of the row it names claims
 * it once that row exists (now, or when its page or sub-page has loaded),
 * brings the row into view and flashes it.
 */
Singleton {
    id: root

    // settings.qml's pages: [{ id, name, icon, component }]. Reassigned when
    // the language changes, which only rebuilds; the files are read once.
    property var pages: []
    property var entries: []
    property var searchIndex: null
    readonly property bool ready: searchIndex !== null

    // { label, section, subsection }, as displayed; empty strings for a section
    // or subsection the index could not name. Null when nothing is being opened.
    property var target: null

    // Sub-pages a page opens from a list kept somewhere else: the widget
    // gallery's cards name theirs in the widgets registry.
    readonly property var subPageSources: ({
        "widgets": "modules/ii/background/widgets/WidgetsRegistry.qml"
    })

    function index(pageList) {
        root.pages = pageList;
        if (reader.busy || root.entries.length > 0)
            return;
        reader.start(pageList.map((page, i) => ({
            page: i,
            path: page.component,
            subPage: ""
        })));
    }

    function query(text, limit) {
        if (!root.searchIndex)
            return [];
        return Search.search(root.searchIndex, text, limit);
    }

    function rebuild() {
        if (root.entries.length === 0)
            return;
        root.searchIndex = Search.buildIndex(root.entries, root.pages, s => Translation.tr(s));
    }

    onPagesChanged: rebuild()

    Connections {
        target: Translation
        function onTranslationsChanged() {
            root.rebuild();
        }
        function onGeneratedTranslationsChanged() {
            root.rebuild();
        }
    }

    // One file at a time; a page's sub-pages join the queue when it is read.
    FileView {
        id: reader
        blockLoading: true
        printErrors: false

        property var queue: []
        property var queued: ({})
        property var current: null
        property var found: []
        property bool busy: false

        function enqueue(file) {
            if (reader.queued[file.path])
                return;
            reader.queued[file.path] = true;
            reader.queue.push(file);
        }

        function start(files) {
            reader.busy = true;
            for (const file of files)
                reader.enqueue(file);
            reader.next();
        }

        function next() {
            if (reader.queue.length === 0) {
                reader.busy = false;
                root.entries = reader.found;
                root.rebuild();
                return;
            }
            reader.current = reader.queue.shift();
            reader.path = FileUtils.trimFileProtocol(Quickshell.shellPath(reader.current.path));
        }

        onLoaded: {
            const file = reader.current;
            const text = reader.text();
            // A source only names sub-pages; it is not drawn in settings.
            if (!file.source) {
                const found = Search.indexFile(text, file.subPage);
                for (const entry of found)
                    entry.page = file.page;
                reader.found = reader.found.concat(found);
            }
            if (!file.subPage) {
                for (const sub of Search.subPagesOf(text))
                    reader.enqueue({ page: file.page, path: `modules/settings/${sub}`, subPage: sub });
                const source = root.subPageSources[root.pages[file.page].id];
                if (source && !file.source)
                    reader.enqueue({ page: file.page, path: source, subPage: "", source: true });
            }
            Qt.callLater(reader.next);
        }
        onLoadFailed: Qt.callLater(reader.next)
    }
}
