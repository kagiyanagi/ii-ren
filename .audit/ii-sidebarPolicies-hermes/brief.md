# ii-sidebarPolicies-hermes — cluster brief

The brief for three rows, `ii-sidebarPolicies-hermes-thread`, `-composer` and `-panels`,
which is how the 19-file / 5,386-line `ii-sidebarPolicies-hermes` row (`hermes/` plus the
five `aiChat/` blocks only Hermes renders) was split. It is past the 2,500-line rule twice
over. The three are one surface, the Hermes tab of the left sidebar, so they get one brief,
as the `ii-bar-*` rows did. Each row's own `brief.md` is its slice.

Read this, then your row's `brief.md`, then your row's `pack.md`. Then `.github/DESIGN.md`
§2, §3, §5, §9.

`Hermes.qml` is the page that hosts all nineteen files, and it belongs to
`ii-sidebarPolicies-root`. Each row edits it only where its brief says so, and only there.

---

## What the Hermes tab is

**Purpose.** Ask the Hermes agent something from the sidebar, read what it answered and
what it did to get there, and answer it when it stops to ask.

**Primary action.** Reading the reply. Everything else on the page is secondary and must
look it: the tool activity the reply was built from, the approval mode, the context meter,
the work and history sheets.

**Hierarchy.** The reply text first. Then anything the agent is *blocked on* (an approval
or a question), which sits over the composer and is the only loud thing on the page. Then
the composer. Then the quiet chrome: turn headers, tool one-liners, the status pill at the
top of the transcript, and the composer's bottom row.

**Reference.** Gemini on Android 16: a column of replies with your own prompts set off to
the side, tool work as a single "show thinking"-style line you can open, and permission
prompts in the Android 16 runtime-permission dialog shape (stacked full-width choices).

---

## Contract 1 — one disclosure recipe

Everything in this tab that folds open uses **`Revealer`**
(`modules/common/widgets/Revealer.qml`). That covers the tool row's details, a tool group's
rows, the think block, a subagent's output tail, and a long result's "Show all". Revealer
already *is* the recipe: it clips, opens on `elementMove` (spatial, may overshoot), and
closes on `elementMoveExit` (monotone, about a quarter as long). Two hand-rolled versions
exist today and both are wrong:

- `ToolActivityRow` animates its own `implicitHeight` but shows the details with
  `visible: root.open` and no clip. On open, the card paints over the next paragraph while
  the height is still growing. On close, it vanishes on the first frame and the height then
  shrinks over nothing.
- `MessageThinkBlock` animates on `elementMoveEnter` in both directions, so its close is its
  open played backwards (DESIGN.md 2.5).

Content inside a fold is **built lazily and kept**: `values: open ? rows : []` (as
`HermesToolSummary` does) destroys the rows on the frame the fold starts closing, so the
Revealer collapses over nothing. Once a fold has opened, its rows stay built.

The chevron rotates on `elementMove`, the spatial spec. A rotation is spatial, and the
Continuity rows already flip theirs this way. It is never `elementMoveFast`.

The header of a fold is its own `RippleButton` (or carries a `StateOverlay`), so hover,
focus and press all show on the whole header (law 6). A raw `MouseArea` that tints a
neighbouring button instead, as the think block does, does not count.

## Contract 2 — one popover recipe

Every floating surface here uses **`ArrowPopupMotion`** on a **zero-size pivot** placed at
the control that opened it. This covers the approval-mode menu, the context breakdown and
the text-selection toolbar. `CalendarPopup` is the worked example: the pivot sits at the
anchor point, and the card hangs off it and is clamped inside the window, so it grows out of
its opener even when the clamp shifts it (DESIGN.md 2.6). Today there are three
hand-assembled copies of the recipe, and each has its own defect:

- `HermesApprovalModeMenu` transcribes the ArrowPopup numbers into a QQC2 `Popup`
  `enter`/`exit`, which is DECISIONS 14's drift, verbatim. The origin is `TopLeft` of a card
  that the clamp shifts sideways.
- `HermesContextMeter` transcribes them again, with its origin at the card's `Bottom`,
  which is not where the pill is once the card is clamped.
- `HermesSelectionActions` binds its root's `visible` to `shown`, so its fade-out never
  plays, and it enters on opacity alone.

Surface: the raw `m3colors.m3surfaceContainerHigh` (opaque, because it floats over text),
`StyledRectangularShadow`, and `rounding.verylarge`. The selection toolbar is a
`rounding.full` pill, which is the Android floating text-selection toolbar. Rows inside a
popover take their states as films over that opaque card. They must not use `colLayer2Hover`,
which is solved for a different base. Dismissal is an outside press (consumed), Escape, or
the sidebar closing. Reparent to the window's content item **from a function, never from a
binding**: `CalendarPopup` records that a `parent:` binding on `QsWindow.contentItem`
re-evaluated during the window rebuild on sidebar open and segfaulted the shell.

## Contract 3 — lists that survive a poll

`HermesService` replaces `subagents` every 2s while a turn runs, `agentProcesses` and
`recentSessions` on every refresh, and `spawnTrees` on every save. A list whose `model:` is
a plain JS array rebuilt from those arrays destroys every delegate on every pass. That
drops the caret out of a half-typed steer, re-runs every entrance, and loses per-row state.
Every such list gets a `ScriptModel` keyed on a stable id: `subagent_id`, a process's
`session_id`, a session's `id`, a spawn tree's `path`, and a side task's `taskId`. The
`ii-sidebarPolicies-continuity` and `todo` rows fixed the same class, and a
`tools/check-*.py` pins it.

## Contract 4 — layers

The page is `colLayer1`. A card on it (a turn, the approval and clarify cards, the console,
the composer) is `colLayer2`. Anything inside such a card (tool details, code, think, the
approval's command) is `colLayer3`, and inside that is `colLayer4`. The work and history
sheets are opaque `colLayer1Base`, laid over the transcript; their rows are `colLayer2`.
`colSurfaceContainer*` tokens are each solved for exactly one base
(`tools/check-dialog-layers.py` explains why), so none of them is painted on a `colLayer*`
card. The code and think headers do this today with `colSurfaceContainerHighest`.

## Contract 5 — one icon button

Four copies of the same transparent 32–34px icon `RippleButton` exist: `InputIconButton`
(`Hermes.qml`, root's), `PanelIconButton` twice (`HermesWorkPanel`, `HermesSideTasksPanel`)
and `HistoryIconButton` (`HermesHistoryPanel`). The panels row collapses its three into one
file, `hermes/HermesIconButton.qml`. The root row later points `InputIconButton` at it.
`AiMessageControlButton` (a `GroupButton` in a `ButtonGroup`) is a different widget, stays,
and is the thread row's.

---

## Fences, for the three rows running at once

1. **Your files only.** Your row's `brief.md` lists them. A file another row owns is
   read-only to you, and anything you find in one goes in your `notes.md` under *Found
   outside the fence*.
2. **`Hermes.qml`** only at the line ranges your brief names.
3. **No git.** No commit, stash, checkout, reset or restore. The dispatcher owns the tree.
4. **No `tools/audit/smoke.sh`, no `pkill`, no `iiren run`.** The desktop is live and is
   running the other two rows' work. The dispatcher runs the shell and takes the shots.
   `qs -c ii ipc call …` against the running shell is fine, and so is qmllint.
5. **No edits to `AGENTS.md`, `QUEUE.md`, `.audit/DECISIONS.md` or `.audit/FINDINGS.md`.**
   Put the `AGENTS.md` paragraph for your new check in your `notes.md` as a block, and the
   dispatcher lands it.
6. **Your own check**, `tools/check-hermes-<row>.py`, in the house shape: pure asserts, no
   framework, logic lifted out of the QML and evaluated under `node` where it is
   arithmetic, structural greps where it is not. Mutation-test it (break the QML, and see it
   fail) and say so in `notes.md`.
