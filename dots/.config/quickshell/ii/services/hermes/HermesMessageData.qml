import QtQuick

/**
 * One turn in a Hermes conversation.
 *
 * Shaped like AiMessageData so the markdown block splitter and the
 * MessageTextBlock / MessageCodeBlock / MessageThinkBlock trio render it
 * unchanged; the extra fields carry what the Hermes gateway streams and the
 * built-in Ai service has no concept of (tool calls, per-turn usage, the
 * approval a turn is parked on).
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
}
