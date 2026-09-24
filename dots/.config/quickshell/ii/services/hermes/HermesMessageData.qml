import QtQuick

/**
 * One turn in a Hermes conversation.
 *
 * Shaped for the markdown block splitter and the MessageTextBlock /
 * MessageCodeBlock / MessageThinkBlock trio; the rest carries what the Hermes
 * gateway streams (tool calls, per-turn usage, the approval a turn is parked
 * on).
 */
QtObject {
    property string role            // user | assistant | interface
    property string content: ""
    property string reasoning: ""   // thinking.delta text, folded into <think> in content
    property string model
    property bool done: false
    property string error: ""

    // Tool activity for this turn: [{ id, name, detail, status, output }]
    // status: running | ok | failed
    property var toolCalls: []

    // message.complete usage payload, kept whole so the footer can show any of it
    property var usage: null

    property bool visibleToUser: true

    /*
     * When this turn was made and when it finished, in ms.
     *
     * Both 0 for a turn rebuilt by session.resume: the gateway stores a
     * conversation's rows without per-message times, so the only stamps a
     * resumed chat could carry are the ones from rebuilding it, which say
     * nothing. The history list carries the session's own start time instead.
     */
    property double createdAt: 0
    property double completedAt: 0

    // Every path that ends a turn goes through `done`, so the finish is stamped
    // here rather than in each of them. First one wins: a late delta that flips
    // done a second time must not restate when the turn ended.
    onDoneChanged: {
        if (done && completedAt === 0 && createdAt > 0)
            completedAt = Date.now();
    }
}
