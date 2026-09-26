# ii-sidebarPolicies-hermes-panels — brief

Split 3/3 of `ii-sidebarPolicies-hermes`. Read `.audit/ii-sidebarPolicies-hermes/brief.md`
first: this row inherits its contracts 3, 4 and 5 and the fences.

**Files (yours).** `hermes/HermesWorkPanel.qml`, `HermesSideTasksPanel.qml`,
`HermesHistoryPanel.qml`, `HermesHistoryRow.qml`, and the new `hermes/HermesIconButton.qml`
(contract 5). In `Hermes.qml`, only the `HermesHistoryPanel { … }` and `HermesWorkPanel
{ … }` blocks, which are the sheets' enter/exit, around lines 604–663.

**Purpose.** Two sheets that cover the transcript. *History* is for finding a past
conversation and opening it. *Work* is for seeing what is running off to the side of this
one (background turns, `btw` questions, delegated children, processes the agent left
running) and steering or stopping it, plus the saved delegation runs.

**Primary action.** History: open a conversation. Work: steer or stop a running child.

**Hierarchy.** History: the search field, then the rows under day headers, with the current
conversation's row tonal. Work: the Live / History tabs, then running items above finished
ones.

**Reference.** The Gemini app's conversation drawer (search on top, rows grouped by day)
and Android 16's per-app "running" list for Work.

**Interaction.**
- *Sheet enter/exit* (in `Hermes.qml`). Keep the pairing (opacity on effects, scale on
  spatial, exit on `elementMoveExit`), but fix the origin. Both sheets open from buttons at
  the **right end of the composer row**, which is *below* the sheet, so `Item.Top` ("the
  edge the button sits under") is backwards. The origin becomes `Item.BottomRight`, the
  corner nearest those buttons.
- *Work → History tab: run list ↔ run detail.* The crossfade-and-shift is fine as a recipe
  and broken as built: `showingDetail` flips before `swapAnim` starts, so both pages' `visible`
  change on frame 1. The old page vanishes, and the *new* one fades out, then back in. The
  visible page follows a second property that the `ScriptAction` flips at the midpoint.
  Switching the Live / History tabs goes through the same fade-through, instead of a
  `visible` snap.
- *Live list* (`HermesSideTasksPanel`). This is contract 3. It is keyed on `kind` plus the
  row's id, and headers are keyed by kind. The `Loader` + `switch` + six inline
  `Component`s become a `DelegateChooser` on `kind`. A steer that is half typed keeps its
  caret through a poll, and an open output tail stays open without re-animating. Both are
  broken now: the list rebuilds every 2s while a turn runs.
- *History list.* This is contract 3, keyed on the session `id` with headers keyed by label.
  It gets the same `DelegateChooser` treatment. The row's delete arming stays: first press
  arms, and a second press or 3s disarms.
- *Buttons.* Every icon button in the four files becomes `HermesIconButton` (contract 5):
  transparent at rest, a hover film over the opaque sheet, `rounding.full`, 32px, with the
  tooltip when one is given, and `iconColor` for the tail toggle.

**Edge states.**
- *History, first open.* `recentSessions` is empty until the gateway answers, so the sheet
  says "No conversations yet" for a moment on a machine that has dozens. Show a loading row
  (`MaterialLoadingIndicator` at inline size) until the first answer. Check whether the
  service exposes a loaded flag before adding one. If it needs a service change, note it
  instead.
- *History, no matches.* `search_off` + "Nothing matching “…”", as now.
- *Work, nothing running.* The `PagePlaceholder`, as now.
- *Work, one child with a long goal.* It wraps and does not elide, as now.
- *A child that stops accepting steer.* The field and send are disabled at `opacity 0.4`,
  and interrupt stays live.

**Cost.** None added. The two `ScrollEdgeFade`s stay. There is one poll timer for open tails
(already shared) and one 1s clock while side tasks run.

**Delete.** `HermesSideTasksPanel`'s non-embedded mode, which has one caller and always
passes `embedded: true`: its own header, `requestClose`, `panelColor`, radius and margins
switch, and the `embedded` property itself. The three in-file icon-button components. The
`Loader`/`Component` switch in both lists.

**Out of scope.** The composer buttons that open the sheets (`InputIconButton`, which is
root's; it adopts `HermesIconButton` in that row). `HermesService`. The settings app, where
account and vault live now.
