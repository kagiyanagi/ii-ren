pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell;
import Quickshell.Io;
import QtQuick;
import qs.modules.common.functions
import "markdownTodo.js" as Md


/**
 * To-do list backed by a Markdown checklist at Config.options.todo.filePath,
 * so the same file can be a note in an editor or vault.
 * Each item is an object with "content", "done", and the "line" it came from.
 */
Singleton {
    id: root
    property string filePath: Config.ready ? (Config.options.todo.filePath || Directories.todoPath) : ""
    property var list: []

    // The file is the state - reparse what we just wrote rather than keeping a
    // second copy of the list around to drift.
    function _save(text) {
        todoFileView.setText(text)
        root.list = Md.parse(text)
    }

    function addTask(desc) {
        _save(Md.append(todoFileView.text(), desc))
    }

    function markDone(index) {
        const item = root.list[index]
        if (item) _save(Md.setDone(todoFileView.text(), item.line, true))
    }

    function markUnfinished(index) {
        const item = root.list[index]
        if (item) _save(Md.setDone(todoFileView.text(), item.line, false))
    }

    function deleteItem(index) {
        const item = root.list[index]
        if (item) _save(Md.remove(todoFileView.text(), item.line))
    }

    function refresh() {
        todoFileView.reload()
    }

    FileView {
        id: todoFileView
        path: root.filePath
        watchChanges: true // Edits made in the other editor show up here
        atomicWrites: true
        onFileChanged: this.reload()
        onLoaded: {
            root.list = Md.parse(todoFileView.text())
            console.log("[To Do] File loaded")
        }
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                // Not created here: writing an empty file would clobber the note
                // if its folder just isn't mounted yet. The first task writes it.
                console.log("[To Do] No file at " + root.filePath)
                root.list = []
            } else {
                console.log("[To Do] Error loading file: " + error)
            }
        }
    }
}
