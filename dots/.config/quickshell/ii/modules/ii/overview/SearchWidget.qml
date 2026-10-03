pragma ComponentBehavior: Bound

import Qt.labs.synchronizer
import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item { // Wrapper
    id: root

    readonly property string xdgConfigHome: Directories.config

    readonly property bool sharpMode: Config.options.appearance.sharpMode
    property string searchingText: LauncherSearch.query
    property var currentResults: []
    property bool showResults: searchingText != ""
    implicitWidth: searchWidgetContent.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: searchWidgetContent.implicitHeight + searchBar.verticalPadding * 2 + Appearance.sizes.elevationMargin * 2

    function focusFirstItem() {
        appResults.currentIndex = 0;
    }

    function focusSearchInput() {
        searchBar.forceFocus();
    }

    function disableExpandAnimation() {
        searchBar.animateWidth = false;
    }

    function cancelSearch() {
        searchBar.searchInput.selectAll();
        LauncherSearch.query = "";
        searchBar.animateWidth = true;
    }

    function setSearchingText(text) {
        searchBar.searchInput.text = text;
        LauncherSearch.query = text;
    }

    Keys.onPressed: event => {
        // Prevent Esc and Backspace from registering
        if (event.key === Qt.Key_Escape)
            return;

        // Handle Backspace: focus and delete character if not focused
        if (event.key === Qt.Key_Backspace) {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                if (event.modifiers & Qt.ControlModifier) {
                    // Delete word before cursor
                    let text = searchBar.searchInput.text;
                    let pos = searchBar.searchInput.cursorPosition;
                    if (pos > 0) {
                        // Find the start of the previous word
                        let left = text.slice(0, pos);
                        let match = left.match(/(\s*\S+)\s*$/);
                        let deleteLen = match ? match[0].length : 1;
                        searchBar.searchInput.text = text.slice(0, pos - deleteLen) + text.slice(pos);
                        searchBar.searchInput.cursorPosition = pos - deleteLen;
                    }
                } else {
                    // Delete character before cursor if any
                    if (searchBar.searchInput.cursorPosition > 0) {
                        searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition - 1) + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                        searchBar.searchInput.cursorPosition -= 1;
                    }
                }
                // Always move cursor to end after programmatic edit
                searchBar.searchInput.cursorPosition = searchBar.searchInput.text.length;
                event.accepted = true;
            }
            // If already focused, let TextField handle it
            return;
        }

        // Only handle visible printable characters (ignore control chars, arrows, etc.)
        if (event.text && event.text.length === 1 && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Return && event.key !== Qt.Key_Delete && event.text.charCodeAt(0) >= 0x20) // ignore control chars like Backspace, Tab, etc.
        {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                // Insert the character at the cursor position
                searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition) + event.text + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                searchBar.searchInput.cursorPosition += 1;
                event.accepted = true;
                root.focusFirstItem();
            }
        }
    }

    StyledRectangularShadow {
        target: searchWidgetContent
    }

    Rectangle { // Background
        id: searchWidgetContent
        clip: true
        implicitWidth: gridLayout.implicitWidth
        implicitHeight: gridLayout.implicitHeight
        // Reads as a pill while collapsed -- 30 is past half of the 56 the bar
        // and its padding come to, so Qt clamps it -- and as an M3E extra-large
        // sheet once the results push it open. `Appearance.rounding.*` is already
        // 0 in sharp mode, through its own multiplier, so there is no ternary.
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colBackgroundSurfaceContainer

        Behavior on implicitHeight {
            id: searchHeightBehavior
            enabled: GlobalStates.overviewOpen && root.showResults
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        // No layer/OpacityMask here. The mask this used to carry was
        // `width x width` -- square, stretched over a card that is always taller
        // than it is wide, so the curvature it drew was not the curvature it was
        // masking to -- and it was masking nothing: every SearchItem is inset
        // `horizontalMargin` from the card edge and the list sits on 4dp-grid
        // margins, so no delegate pixel reaches the corner radius. Two
        // framebuffers for a correction that was both wrong and unnecessary
        // (DESIGN.md 8). `clip` above and on the list does the rest.
        GridLayout {
            id: gridLayout
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 1

            SearchBar {
                id: searchBar
                property real verticalPadding: 4
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 4
                Layout.topMargin: verticalPadding
                Layout.bottomMargin: verticalPadding
                Synchronizer on searchingText {
                    property alias source: root.searchingText
                }
            }

            // Field and results are separated by whitespace on the 4dp grid --
            // 4 below the bar plus the list's own 12 -- not by a rule (11).
            StyledListView { // App results
                id: appResults
                visible: root.showResults && count > 0
                Layout.fillWidth: true
                implicitHeight: Math.min(Appearance.sizes.searchResultsMaxHeight, appResults.contentHeight + topMargin)
                clip: true
                topMargin: 12
                // Layout space, not a scroll `bottomMargin`: a scroll margin only
                // pads the end of the content, so mid-scroll a row drew to the
                // card's edge and its flat-clipped corners stuck out past the
                // 30 radius (rows are inset only 12). Ending the clip 12 above
                // the edge keeps every row inside the curve.
                Layout.bottomMargin: 12
                // Assigning a model destroys every delegate and builds them
                // again -- QQmlDelegateModel::setModel emits a remove of the old
                // count and an insert of the new one -- so with the shared list's
                // enter and exit transitions on, a query that changed one row's
                // text slid every row out and scaled every row back in. The set
                // is replaced, not added to; the card's own height animation is
                // the motion this surface has (2.1). Same reason as the
                // bluetooth, wifi and mixer lists.
                animateAppearance: false
                KeyNavigation.up: searchBar

                onFocusChanged: {
                    if (focus)
                        appResults.currentIndex = 1;
                }

                Connections {
                    target: root
                    function onSearchingTextChanged() {
                        if (appResults.count > 0)
                            appResults.currentIndex = 0;
                    }
                }

                // Assigned here rather than bound to `LauncherSearch.results`
                // so the model is current before the index is put back: the
                // binding and this handler hang off one change signal in an
                // undefined order.
                //
                // The whole list, not a slice of it. This used to hand over the
                // first 15 and then assign the full set again 200ms later, which
                // bought nothing -- a ListView instantiates what fits its
                // viewport, 11 rows here, whether `count` is 15 or 57 -- and cost
                // two more rebuilds of every delegate per query.
                Connections {
                    target: LauncherSearch
                    function onResultsChanged() {
                        root.currentResults = LauncherSearch.results;
                        root.focusFirstItem();
                    }
                }

                model: root.currentResults

                delegate: SearchItem {
                    id: searchItem
                    // The selectable item for each search result
                    required property var modelData
                    anchors.left: parent?.left
                    anchors.right: parent?.right
                    entry: modelData
                    query: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch])

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Tab) {
                            if (LauncherSearch.results.length === 0)
                                return;
                            const tabbedText = searchItem.modelData.name;
                            LauncherSearch.query = tabbedText;
                            searchBar.searchInput.text = tabbedText;
                            event.accepted = true;
                            root.focusSearchInput();
                        }
                    }
                }
            }

            // Unreachable in the shipped config -- `showDefaultActionsWithoutPrefix`
            // synthesises Command / Math result / Web search for any string -- but a
            // prefix search empties the list, and this used to leave a field with a
            // void under it.
            Loader {
                Layout.fillWidth: true
                Layout.preferredHeight: Appearance.sizes.pagePlaceholderHeight
                active: root.showResults && appResults.count === 0
                visible: active
                sourceComponent: PagePlaceholder {
                    icon: "search_off"
                    title: Translation.tr("No results")
                    description: Translation.tr("Nothing matched that search")
                }
            }
        }
    }
}
