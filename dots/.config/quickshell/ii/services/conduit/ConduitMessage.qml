import QtQuick

/**
 * Represents one turn in a Conduit conversation.
 * Roles: "user", "assistant", "interface" (local notices, never sent upstream).
 *
 * `content` is the plain-text form, used for user/interface turns, for building
 * request history, and for persistence. Assistant turns additionally carry
 * `parts` — the ordered text/tool pieces used for rendering.
 */
QtObject {
    property string role
    property string content
    property string rawContent
    property string model

    // Absolute paths attached to this turn. Kept separate from `content` so the UI can
    // show them as previews; the request builder folds them into the text it sends.
    property var attachments: []

    // list<ConduitPart>, reassigned when a part is added so bindings notice
    property var parts: []

    /**
     * Voice memo for this turn, synthesised on demand. Lives in /tmp and is
     * deliberately left out of saved chats: reopening a week-old conversation
     * should not carry a megabyte of audio per reply with it.
     */
    property string audioPath
    property int audioBytes: 0
    property var audioBars: []

    property bool thinking: false
    property bool done: false
    property bool visibleToUser: true
    property string error
}
