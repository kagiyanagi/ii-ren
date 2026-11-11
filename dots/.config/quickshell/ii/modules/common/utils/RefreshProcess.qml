import QtQuick
import Quickshell.Io

/**
 * A Process that reads some state, re-run with refresh() whenever that state may have
 * changed. Quickshell 0.3.2 queues one re-run for `running = true` during a run,
 * coalescing further starts and reading the command again at restart time. This
 * wrapper also batches calls in one tick and keeps the same refresh contract on
 * versions without that queue: a call during a run gets one more read after it.
 * It is for replaceable reads, not distinct mutations that each need to run.
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
