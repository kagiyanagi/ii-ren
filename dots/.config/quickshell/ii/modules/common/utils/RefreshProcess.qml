import QtQuick
import Quickshell.Io

/**
 * A Process that reads some state, re-run with refresh() whenever that state may have
 * changed. `running = true` on a running Process is a no-op, so the change that asked
 * for a read while one was under way was simply lost, and the answer that landed could
 * predate it. Here calls in one tick start one run, and a call during a run gets one
 * more run after it: the answer is never older than the last refresh().
 */
Process {
    id: root

    property bool _again: false

    function refresh() {
        Qt.callLater(root._start);
    }

    function _start() {
        if (root.running)
            root._again = true;
        else
            root.running = true;
    }

    onRunningChanged: {
        if (root.running || !root._again)
            return;
        root._again = false;
        root.refresh();
    }
}
