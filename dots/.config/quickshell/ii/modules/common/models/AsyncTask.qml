pragma ComponentBehavior: Bound
import QtQuick

/**
 * State machine for a background job that can fail: a subprocess, an API call.
 */
NestableObject {
    id: root

    enum State {
        Done, Preparing, Processing, Error
    }

    signal finished()
    signal error(message: string)
    property string errorMessage: ""
    property var state: AsyncTask.State.Done

    function resetState() {
        root.state = AsyncTask.State.Done;
        root.errorMessage = "";
    }

    function fail(message: string) {
        root.state = AsyncTask.State.Error;
        root.errorMessage = message;
        root.error(message);
    }

    function succeed() {
        root.state = AsyncTask.State.Done;
        root.finished();
    }
}
