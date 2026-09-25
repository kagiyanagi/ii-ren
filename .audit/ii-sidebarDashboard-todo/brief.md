# ii-sidebarDashboard-todo — brief

**Purpose.** Jot a task down and tick it off from the sidebar, against the Markdown
checklist the user also keeps in their vault.

**Primary action.** Adding a task. It is an always-visible "Add a task" field at the foot of
the widget: type, Enter. The filled round add button beside it is the same action for the
pointer. Ticking a task off is second, and is the leading circle on each row.

**Hierarchy.** The task text first, then each row's leading circle, then the add field,
then the Unfinished/Done tabs, then the delete buttons in `colSubtext`.

**Reference.** Google Tasks, the side-panel form of it (M3). It is the same job in the same
narrow column: a circle checkbox leading each row, the text beside it, and "Add a task"
always present rather than behind a FAB. The Android app's FAB and bottom sheet need a
screen of height, and this widget has about 300px.

**Interaction.**
- *Row.* One line: circle, text (wraps), delete. Rows are `colLayer2` cards on the group's
  layer 1, `rounding.small`, 4 apart. Min height 40, from 32px icon buttons plus 4 of
  padding. The buttons were 30px and square-cornered. They are 32 (3.4), `rounding.full`
  (the icon-button recipe), with layer-2 hover and ripple.
- *Done.* The circle fills (`check_circle`, `colPrimary`). The text goes `colSubtext` and is
  struck through. The undo is the same circle.
- *List motion.* A row leaves on `StyledListView`'s remove (exit spec, slides out), and its
  neighbours close the gap on `elementMove`. A new row fades in, no pop-in scale on a
  full-width row. This needs the model to know which row changed. `Todo.list` is reparsed on
  every write, so every object is new, and the `ScriptModel` without a key rebuilt every
  delegate on every tick. It is keyed on the content plus its occurrence count now.
  A keyed match with new values is a `dataChanged`, so `originalIndex` still updates.
- *Field.* `ToolbarTextField` (pill, hover and focus films), `colLayer2`. Enter adds. Escape
  clears text if there is any, else it passes through so the sidebar still closes. `N`
  focuses the field. After adding, the view goes to Unfinished and jumps to the end, where
  `markdownTodo.append` put the task.

**Edge states.**
- *Empty:* `PagePlaceholder` on each tab, as now. The add field is still there.
- *No file yet* (vault not mounted): the same as empty. The first add writes the file (service,
  unchanged).
- *One item:* one row, top of the list.
- *Long text:* wraps. The circle and delete stay on the first line.

**Cost.** The FAB's `StyledRectangularShadow` goes with the FAB. Nothing repeats an effect;
each row's two `RippleButton`s are the shared widget's own cost.

**Delete.** The FAB and its shadow. The scrim-and-card add dialog, its raw `TextField`, and
its opacity fade that exited on the enter spec (2.5). The action row under each task, which
doubled every row's height. The dead `enableHeightAnimation`/`pendingDoneToggle`/
`pendingDelete` properties, and `listBottomPadding`, which nothing read. That is why the FAB
sat on top of the last row's buttons. The unused `Qt5Compat.GraphicalEffects` import. The
`originalIndex` map, which was done twice.

**Out of scope.** `services/Todo.qml` and `markdownTodo.js`, which just landed and are pinned
by the vault format. Editing a task's text in place. Undo for delete, which was one click
before and still is. The background widget library's own `TodoWidget`, which is vendored.
