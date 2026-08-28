import QtQuick

/**
 * One ordered piece of an assistant turn.
 *
 * A turn is no longer a single string: the CLI interleaves text blocks with tool
 * calls, so "read the file, say something, write a file, say something else"
 * arrives as five separate pieces that must render in order.
 *
 * Parts are QObjects rather than plain JS objects so streaming can mutate `text`
 * or `toolResult` in place and have the delegate update, without reassigning the
 * whole parts array on every token.
 */
QtObject {
    // "text" — markdown, may contain ``` fences and <think> blocks
    // "tool" — a tool invocation and its result
    property string kind: "text"

    property string text

    property string toolId
    property string toolName
    property string toolInput      // Pretty one-line summary of the arguments
    property string toolResult
    property bool toolFailed: false
    property bool toolRunning: true
}
