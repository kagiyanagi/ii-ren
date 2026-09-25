#!/usr/bin/env python3
"""The sidebar to-do list animates the one row that changed, and acts on the right task.

`Todo.list` is reparsed from the Markdown file on every write, so every object in it is
new each time. A `ScriptModel` without `objectProp` compares by identity, so every tick,
add and delete rebuilt every row, and no row ever slid out. It is keyed now. The key must
be unique, even with two identical tasks, or ScriptModel matches the wrong row. It must
also stay the same when a task is ticked or a task above it is deleted, or that is a
rebuild again. A keyed match with new values is a `dataChanged`, which is what carries the
fresh `originalIndex` to the row. The service takes that index, so a stale one ticks or
deletes a different line of the user's note. None of this shows in a screenshot.

The `tasks` binding is lifted out of TodoWidget.qml and run under node.
"""
import json
import re
import subprocess
from pathlib import Path

TODO = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii/modules/ii/sidebarDashboard/todo"
widget = (TODO / "TodoWidget.qml").read_text()
tasklist = (TODO / "TaskList.qml").read_text()

assert re.search(r'ScriptModel \{[^}]*objectProp: "key"', tasklist, re.S), "TaskList's ScriptModel must be keyed on `key`"
assert "values: root.taskList" in tasklist
for dead in ("FloatingActionButton", "colScrim", "listBottomPadding"):
    assert dead not in widget + tasklist, f"{dead} is back: the add dialog/FAB was replaced by the inline field"

body = re.search(r"readonly property var tasks: \{(.*?)\n    \}", widget, re.S).group(1)


def tasks(items):
    js = f"const Todo = {{ list: {json.dumps(items)} }};\nconsole.log(JSON.stringify((() => {{{body}\n}})()));"
    return json.loads(subprocess.run(["node", "-e", js], capture_output=True, text=True, check=True).stdout)


def task(content, done=False, line=0):
    return {"content": content, "done": done, "line": line}


before = tasks([task("a", line=0), task("b", line=1), task("a", line=2), task("c", line=3)])
keys = [t["key"] for t in before]
assert len(set(keys)) == len(keys), f"keys collide on a duplicate task: {keys}"
assert [t["originalIndex"] for t in before] == [0, 1, 2, 3]

# Ticking changes no key.
ticked = tasks([task("a", line=0), task("b", True, 1), task("a", line=2), task("c", line=3)])
assert [t["key"] for t in ticked] == keys, "ticking a task must not change any key"

# Deleting "b" keeps every other key, and the rows below it get their new index.
deleted = tasks([task("a", line=0), task("a", line=1), task("c", line=2)])
by_key = {t["key"]: t["originalIndex"] for t in deleted}
assert set(by_key) == set(keys) - {keys[1]}, f"delete must remove exactly one key: {keys} -> {list(by_key)}"
assert by_key[keys[3]] == 2, "the row below a delete must carry its new index"

print("check-todo: ok")
