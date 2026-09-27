# waffle-startMenu — notes

**Opening it.**
- Active under `Config.options.panelFamily: "waffle"` (or cycling via `qs -c ii ipc call panelFamily cycle`).
- Toggled via `qs -c ii ipc call search toggle`, `search` IPC methods (`open`, `close`), or the Start / Search buttons on `WaffleBar`.
- Global shortcuts: `searchToggle` (`Super` key), `overviewClipboardToggle`, and `overviewEmojiToggle`.

**Measured and fixed.**
- **Exit animations restored via Loader lifecycle:** `WaffleStartMenu.qml` originally bound `panelWindow.visible: GlobalStates.searchOpen`. When `searchOpen` was toggled off, the Wayland surface was immediately unmapped, cutting off the 150ms `closeAnim` in `WBarAttachedPanelContent`. Adopted the `Loader` latching pattern (consistent with `WaffleNotificationCenter.qml`): `panelLoader.active = true` on open, closing triggers `content.close()`, and `content.onClosed` sets `panelLoader.active = false` after the slide-out completes.
- **Screen lock safety gating:** Added `onScreenLockedChanged` listener in `WaffleStartMenu.qml` to ensure `searchOpen` is closed when the screen locks, and gated `HyprlandFocusGrab.active` on `!GlobalStates.screenLocked`.
- **Search preview null-pointer exceptions:** In `searchPage/SearchResults.qml`, `ResultPreview` attempted to access `resultPreview.entry.type`, `resultPreview.entry.verb`, and `resultPreview.entry.actions` when no results matched. Added null guards (`resultPreview.entry != null && resultPreview.entry.name`), gated `ResultPreview.visible: Boolean(resultList.model && resultList.model.length > 0 && resultPreview.entry && resultPreview.entry.name)`, and made `actionsColumn.model` return `[]` when `!resultPreview.entry || !resultPreview.entry.name`.
- **Prevented unparented QObject memory leaks:** `SearchResults.qml` created dynamic `LauncherSearchResult` items using `searchResultComp.createObject(null, ...)`. Over typing sessions, unparented QObjects accumulated in memory. Explicitly parented them to `resultListView` and `actionsColumn`. Similarly, `AllAppsGrid.qml` now parents `AggregatedAppCategoryModel` instances to `root`.
- **Filtered phantom null entries in pinned apps:** In `startPage/StartPageApps.qml`, `Config.options.launcher.pinnedApps.map(...)` now includes `.filter(app => app != null)` to safely ignore uninstalled application IDs without instantiating blank button delegates.
- **AggregatedAppCategoryModel startup safety:** In `startPage/AppCategoryGrid.qml`, safe optional chaining (`root.aggregatedCategory?.categories ?? []`) prevents `TypeError` before category models are assigned.
- **Cleaned SearchBar hierarchy and focus area:** Removed the redundant inner `searchInputBg` rectangle (which had `anchors.margins: 1` violating design guidelines), moved borders directly onto `outline`, corrected spacing/margins to 12dp, and updated `MouseArea` to accept `Qt.LeftButton` with `onClicked: root.forceFocus()`.
- **Escape key navigation handling:** Fixed `StartMenuContent.qml`'s `Keys.onPressed` to clear the search query if active, or invoke `root.close()` if on the start page. Added `closeRequested` signal on `SearchBar.qml` so pressing Escape inside `TextInput` also propagates properly.
- **Resolved component ID shadowing:** In `startPage/AppCategoryGrid.qml`, renamed `component SmallGridButton: WButton { id: root }` to `id: buttonRoot` to prevent shadowing the outer `Rectangle { id: root }`.
- **Auto-dismissing popups on search close:** Added `GlobalStates.onSearchOpenChanged` connections in `AppCategoryGrid.qml` (`categoryFolderPopup`), `StartUserButton.qml` (`userMenu`), and `TagStrip.qml` (`accountsMenu`) to ensure flyout popups close cleanly when the start menu closes.
- **Session power action close behavior:** In `startPage/StartPageContent.qml` and `startPage/StartUserButton.qml`, triggering Lock, Sleep, Shut down, Restart, or Sign out now sets `GlobalStates.searchOpen = false` to dismiss the menu.
- **Replaced hardcoded animation durations:** In `startPage/AppCategoryGrid.qml`, replaced `duration: 300` with `Appearance.animation.elementMoveNormal.duration` and `duration: 200` with `Appearance.animation.elementMoveExit.duration`. Added `Appearance.animation.elementMoveFast.duration` to button scale animations.
- **Grid alignment and token cleanliness:** Corrected 20 off-4dp-grid numbers across the module:
  - `SearchBar.qml`: eliminated 1px margin, `spacing: 11` -> 12, `leftMargin: 14` -> 12, `implicitSize: 18` -> 16.
  - `searchPage/SearchPageContent.qml`: `topMargin: 2` -> 0.
  - `searchPage/SearchResultButton.qml`: `verticalPadding: 11` -> 12, `implicitHeight: 62` -> 64, `implicitWidth: 47` -> 48, `implicitSize: 14` -> 16.
  - `searchPage/SearchResults.qml`: `preferredWidth: 386` -> 384, margins 1 -> 0, `margins: 22` -> 24, `spacing: 13` -> 12, `topMargin: 10` -> 12, `implicitHeight: 38` -> 40.
  - `searchPage/TagStrip.qml`: `+ 10` -> `+ 8`.
  - `startPage/AllAppsGrid.qml`: `columnSpacing: 27` -> 28.
  - `startPage/AppCategoryGrid.qml`: `implicitWidth/Height: 156` -> 152, `margins: 10` -> 8, `rightMargin: -19` -> -20, `implicitSize: 34` -> 32.
  - `startPage/StartAppButton.qml`: `spacing: 3` -> 4, `implicitSize: 34` -> 32.
  - `startPage/StartPageApps.qml`: `topMargin: 25` -> 24, `bottomMargin: 30` -> 32, `spacing: 26` -> 24.
  - `startPage/StartPageContent.qml`: footer `implicitHeight: 63` -> 64.
  - `startPage/StartUserButton.qml`: `x: -51` -> -52, `y: ... - 10` -> -8, `horizontalPadding: 10` -> 12, `verticalPadding: 7` -> 8, `spacing: 5` -> 4, `leftMargin: 6` -> 8, `implicitWidth: 334` -> 336, `bottomMargin: 7` -> 8, `sourceSize: 58` -> 56.
- **Modern QML Bound ComponentBehavior:** Added `pragma ComponentBehavior: Bound` to all 17 QML files. Removed unused `Qt5Compat.GraphicalEffects` imports.

**Automated verification.**
- Added `tools/check-waffle-startmenu.py` validating pragma across all 17 files, exit animation latching, screen lock gating, SearchBar structure and Escape handling, SearchResults null safety and parentage, category popup animations, and 4dp grid metrics.
- Verified with `python3 tools/check-design.py --diff`: 0 findings, 0 errors.
