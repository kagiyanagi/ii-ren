# ii-sidebarPolicies-hermes-panels — notes

Split 3/3 of `ii-sidebarPolicies-hermes`. Ran alone, so this session ran the shell and
took the shots itself.

## What landed

- **`HermesIconButton.qml`** (new): round, 32px, transparent at rest, layer 1 films,
  tooltip when given, `iconColor`. It replaces `PanelIconButton` twice and
  `HistoryIconButton` once. Buttons on a layer 2 card go through an in-file
  `CardIconButton` that passes `colLayer2Hover`/`colLayer2Active`. The 28px overrides are
  gone, so every one is 32.
- **Live list** (`HermesSideTasksPanel`): a `ScriptModel` keyed on `key` (the kind for
  headers; `taskId`, `subagent_id` or `session_id` for rows; the index only where the
  gateway sent none) behind a `DelegateChooser` on `kind`. The `Loader` + `switch` + six
  `Component`s are gone. The three headers are one `SectionHeader` with a default slot for
  their actions. Running side tasks sort above finished ones. The subagent card's
  `Behavior on implicitHeight` is deleted, because the `Revealer` inside it already
  animates. A child that refuses steer shows its field at 0.4, and interrupt stays live.
  The non-embedded mode is deleted (header, `requestClose`, `panelColor`, radius, the
  margin switch, `embedded`). So are its own refresh-on-show handlers, because
  `HermesWorkPanel` already refreshes it.
- **Work sheet**: `PageSwap`, an in-file fade-through. `page` is the request and
  `shownPage` is what is drawn, and only the `ScriptAction` at the midpoint moves
  `shownPage`. The old page leaves on `elementMoveExit` (opacity and a 12px `Translate`).
  The new one arrives with its shift on `elementMoveEnter` and its opacity on
  `elementMoveFast`. The Live/History tabs and the run list/detail both use it.
  `closeDetail`, `swapOpacity`, `swapShift` and the hand-built `SequentialAnimation` are
  gone. The saved-run list is keyed on `path`. The `Component.onCompleted` refresh is gone,
  because nothing mounts the sheet through a `Loader` and it fired at page build with the
  sheet hidden.
- **History sheet**: keyed on `session:<id>` / `header:<label>`, with a `DelegateChooser`.
  A loading row (inline `MaterialLoadingIndicator`, "Loading conversations…") shows until
  `recentSessions` first changes. Rows are bare on the sheet (drawer style), so their
  films are layer 1's, not the `colLayer2Hover` they had.
- **History row**: the delete button is a `HermesIconButton`. Unarmed, its hover is a
  `StateOverlay` film, because a replacement colour equals the row's own hover exactly and
  pointing at the bin looked like pointing at the row (design-check WARN, fixed and seen).
- **`Hermes.qml`** (the two sheet blocks only): `transformOrigin: Item.BottomRight`.

## Decided, not in the brief

- **History rows stay bare**, not `colLayer2` cards as contract 4 says for sheet rows.
  The reference is the Gemini drawer, and the brief's own hierarchy (current row tonal)
  implies the rest are not. The Work rows are `colLayer2` cards as contracted.
- **The loading flag is local.** `HermesService` has none, and the brief says to note a
  service change rather than make one. The ceiling is marked `ponytail:` in
  `HermesHistoryPanel.qml`: a failed `session.list` never assigns, so a dead gateway keeps
  the loading row. The fix is a `recentSessionsLoaded` set in `refreshRecentSessions`'s
  callback on both paths.

## How it was seen

- Live: the Work sheet (Live empty, History empty), a Live→History swap caught at 60ms
  (only the outgoing page, shifted up and fading), the History sheet at 50ms into the
  enter and 40ms into the exit (both scaled about the bottom-right corner), a row's hover,
  the bin's own film on a hovered row, and the armed bin.
- Probe (`qs -p`, a throwaway file removed after): the Live list with two side tasks, two
  children (depth 0 and 1, one refusing steer) and a process, then a second poll of fresh
  objects. **All 8 delegates were the same objects after the poll.** `HermesService.missing
  = true` in the probe stops `call()` from starting a second gateway.
- agy vision (`gemini-3.1-pro-high`, `--mode plan`): four findings. One was real (finished
  side work above running) and is fixed and pinned. "No tonal row" is correct, because
  the current conversation is new and not in the list yet. The title row above the tabs
  and the section headers are kept on purpose.
- Not seen: the loading row (the list had already answered by the time the sheet was
  opened after a restart), a tonal current row, and a live steer surviving a poll with
  text in it. The probe proved the delegate survives, which is what the caret depends on.

## For the cohesion pass (motion)

- The Work tab and run-detail fade-through: watch that the old page never reappears and
  the new one does not fade out first.
- Both sheets now grow from the bottom right. Check they read as coming out of the
  composer-row buttons.

## Follow-ups

- `InputIconButton` (`Hermes.qml`, root's) was meant to adopt `HermesIconButton` in the
  root row, which ran first. It still carries its own copy with a badge.
- `PageSwap` is the second in-file fade-through (`BottomWidgetGroup.TabSwitchAnim`). It is
  a candidate for `modules/common/widgets/`.
- `SecondaryTabBar` draws a full-width track line under the tabs (rule 11). It is a shared
  widget, outside this row.

## Check

`tools/check-hermes-panels.py`. Mutation-tested with eleven breaks: position-keyed
children, a task key with no index fallback, a session key that changes per refresh, an
unkeyed history model, the detail page reading `showingDetail`, a midpoint that does not
move `shownPage`, the run list keyed on `label`, `Item.Top` in `Hermes.qml`, the disabled
steer field at full opacity, the placeholder's `shown` ungated on loading, and the sort
removed. Each failed with its own message. One more (the placeholder container's
`visible` ungated) passed, and it is benign: `shown` still hides the placeholder.
