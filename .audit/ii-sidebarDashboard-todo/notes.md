# ii-sidebarDashboard-todo — notes

**Opening it.** `qs -c ii ipc call sidebarRight open`, then To Do in the bottom group's rail
(about `1523,845` on this 1920x1080 screen). Persistent keeps the rail's tab in
`states.sidebar.bottomGroup.tab`. It was 0 (Calendar) before this session and is now 1.
Unfinished/Done are at `y≈678`, and the add field is at `y≈988`.

**The list is the user's real note.** `todo.filePath` points into their Obsidian vault. Every
live test was done in pairs: add then delete, tick then untick. The file was compared
byte-for-byte against a copy taken first (`cmp`) and came back identical. Do the same next
time, or point `todo.filePath` somewhere scratch.

**Verified live.** Add by Enter, tick, untick, delete, and Escape (the first clears, the
second closes the sidebar). A `grim` burst during a mid-list tick showed the row sliding out
and its neighbours closing the gap over about five frames. Before the key, the whole list
was rebuilt. A delete at the very end of a scrolled list shows no slide, because the view
snaps up as the content shrinks. That is ListView, not the model.

**Why the key is content plus a count.** `line` is not stable: a delete shifts every task
below it, so each of those rows would read as removed and re-inserted. Content alone
collides on duplicate tasks. `check-todo.py` was mutation-tested against both.

**Rejected.** Keeping the FAB with a bottom sheet. The widget is about 300px tall, and the
FAB already sat on the last row's buttons, because `listBottomPadding` was declared and
never read. Replacing the tabs with a Google Tasks "Completed (N)" section. It is closer to
the reference, but it needs a footer or a sectioned model, and the tabs with PageUp/PageDown
are already familiar. Revisit it if the tabs feel redundant under the rail.

**Not done.** The agy/Gemini vision pass. `smoke.sh` did run, and it restarted the shell.

**For the cohesion pass (motion).** Ticking or deleting a task now plays `StyledListView`'s
remove (the row slides out on `elementMoveExit`, and the rows below move up on
`elementMove`). Adding one fades it in on `elementMoveFast`. Before, none of these
animated: `animateAppearance` was off, and the model was rebuilt on every write anyway.
