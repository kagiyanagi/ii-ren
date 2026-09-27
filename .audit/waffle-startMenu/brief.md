# waffle-startMenu — brief

**Purpose.** The primary application launcher and unified search surface for the Waffle panel family (Windows 11 Fluent style). Houses pinned applications, categorized all-apps folders, real-time indexed search (apps, actions, clipboard, emojis, math, shell commands, web search) with category filtering tag strips, preview pane with app actions/shortcuts, user profile card with account management, and session power actions.

**Primary action.** Launching an application or searching for apps/commands/clipboard items via keystrokes. Secondary: organizing/pinning apps to start or taskbar, browsing categorized app folders, and executing power/session actions.

**Hierarchy.**
1. **Search Bar** (top): Persistent unified search input with focus management, prefix synchronization, and clear/close triggers.
2. **Start Page** (active when search query is empty):
   - **Pinned Section**: 8-column grid of user-pinned application launchers with right-click contextual management (Move front/left/right, Pin/Unpin).
   - **All Apps Section**: 4-column category grid showing mini-grids of apps with drill-in popup folders and vertical pagination.
   - **Footer**: User profile button (opening Megahard account popup and Sign out) and power button (Lock, Sleep, Shut down, Restart).
3. **Search Page** (active when search query is non-empty):
   - **Tag Strip**: Horizontal filter pill list ("All", "Apps", "Actions", "Clipboard", "Emojis", "Math", "Commands", "Web") and quick options menu.
   - **Search Results & Preview**: Split view with categorized result list (with "Best match" highlight) and rich preview card with deep actions (Open, Pin to Start/Taskbar, App Actions).

**Reference.** Windows 11 Start Menu and Search flyout adapted to ii-ren design tokens and M3 Expressive / Fluent guidelines (`.github/DESIGN.md`).

**What is wrong, measured.**
- **Premature surface unmapping breaks exit animations:** `PanelWindow` in `WaffleStartMenu.qml` used `visible: GlobalStates.searchOpen`. Toggling `searchOpen` to `false` instantly unmapped the Wayland layer surface, destroying the window before `content.close()` could run its 150ms `closeAnim`.
- **Missing screen lock gating:** `WaffleStartMenu.qml` lacked checks on `GlobalStates.screenLocked`, allowing the start menu and its focus grab to remain active over or open on top of the lock screen.
- **Null pointer TypeErrors in search preview:** When a search returned 0 matches, `ResultPreview` in `SearchResults.qml` threw `TypeError` trying to access `actions`, `type`, and `verb` on an empty or null entry.
- **Unparented dynamic QObject memory leak:** In `SearchResults.qml`, dynamic `LauncherSearchResult` items in `resultList.model` and `actionsColumn.model` were created using `searchResultComp.createObject(null, ...)`. Over repeated typing sessions, hundreds of unparented objects leaked. Similarly, `AllAppsGrid.qml` created unparented `AggregatedAppCategoryModel` objects with `null`.
- **Ghost null app buttons:** If an uninstalled app remained in `Config.options.launcher.pinnedApps`, `DesktopEntries.byId(appId)` produced `null`, creating empty button stubs in `StartPageApps.qml`.
- **Startup crash on null category access:** In `AppCategoryGrid.qml`, `root.aggregatedCategory.categories` was evaluated directly without null safety during initialization, throwing `TypeError: Cannot read property 'categories' of null`.
- **Search bar click and structure flaws:** `SearchBar.qml` nested an inner `Rectangle` with `anchors.margins: 1` inside an outer border `Rectangle`, and had a dummy `MouseArea` with `acceptedButtons: Qt.NoButton` that failed to focus the `TextInput` when clicking outside the text bounds.
- **Escape key navigation failure:** In `StartMenuContent.qml`, overriding `Keys.onPressed` without invoking `root.close()` on Escape prevented the start menu from closing when pressing Escape.
- **Component root ID shadowing:** In `AppCategoryGrid.qml`, `component SmallGridButton` declared `id: root`, shadowing the file-level `Rectangle { id: root }`.
- **Folder and menu persistence on menu close:** Closing the start menu while a category folder popup or account popup was open left the popups in an opened state for the next session.
- **Session action start menu retention:** Clicking Lock, Sleep, Restart, or Shut down in `StartPageContent.qml` did not close the start menu flyout.
- **Hardcoded animation durations:** `AppCategoryGrid.qml` hardcoded `duration: 300` and `duration: 200` instead of using `Appearance.animation.*.duration` tokens.
- **Deterministic 4dp grid violations:** 20 off-grid metrics across 6 files (`SearchBar.qml`, `SearchResults.qml`, `SearchResultButton.qml`, `StartAppButton.qml`, `StartPageApps.qml`, `StartUserButton.qml`).
- **Missing ComponentBehavior: Bound:** 5 of 17 QML files lacked `pragma ComponentBehavior: Bound`.

**Interaction.**
- Super key or start button opens start menu: slides in from bar edge (200ms `Looks.transition.enter`).
- Super key, Escape, or clicking outside slides out the panel (150ms `Looks.transition.exit`); layer surface unmaps only after `onClosed`.
- Typing immediately redirects to search bar, queries `LauncherSearch`, and swaps to `SearchPageContent`.
- Escape clears active search query first; pressing Escape on an empty search closes the flyout.
- Arrow keys navigate search results smoothly.
- Enter executes highlighted search result and closes start menu.

**Edge states.**
- Empty search results: preview card gracefully hides, result list avoids index bounds out-of-range exceptions.
- Uninstalled pinned apps: filtered out gracefully; no phantom buttons rendered.
- Screen lock triggered: Start menu closes immediately and releases focus grab.
- Category folder popup: auto-dismisses if start menu closes.

**Cost.**
- Prevents memory leaks by parenting dynamically allocated search results and category models.
- Avoids multiple runtime TypeErrors during search and category browsing.

**Delete.**
- Redundant nested outline rectangle in `SearchBar.qml`.
- Unused `import Qt5Compat.GraphicalEffects` in `BigAppGrid.qml`, `StartAppButton.qml`, `StartPageContent.qml`, and `StartUserButton.qml`.
- String-based `"ProxyWindow"` traversal hack in `AppCategoryGrid.qml`.

**Out of scope.**
- Rewriting `LauncherSearch` search indexing or modifying global `DesktopEntries` service.
