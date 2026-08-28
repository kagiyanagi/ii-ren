import QtQuick

/**
 * Base class for a provider's transport and wire format, so adding a provider
 * means dropping in one file.
 *
 * buildScript(request) returns the whole bash script to run, plus a `payload`
 * string. The service writes `payload` to `request.payloadPath` and the script
 * reads it from there, so user-authored text is never escaped into a command
 * line and never shows up in the process list.
 *
 * request: { provider, modelId, messages, systemPrompt, payloadPath, sessionId,
 *            workingDir, attachDir, enableTools, permissionMode, disallowedTools,
 *            desktopMcp, continuing }
 * returns: { script, payload }, or { error } for a request it cannot build.
 *
 * A provider whose `persistentProcess` capability is set serves many turns from
 * one process, so it splits buildScript in two: buildProcessScript(request) for
 * how to launch the CLI, and buildTurnPayload(request) for one turn as a payload
 * written to that process's stdin. Providers that start a process per turn need
 * neither.
 *
 * parseLine(line, message) decodes one line of the process's stdout into a
 * delta for the service to apply. Strategies never mutate the message
 * themselves: turn assembly — ordering streamed text against tool calls —
 * stays in one place instead of being duplicated per provider.
 *
 * Recognised delta keys:
 *   textDelta, thinkingDelta, newBlock, toolStart {id, name},
 *   toolCalls [{id, name, input}], toolResults [{id, content, failed}],
 *   sessionId, cost, rateLimit, tokenUsage {input, output}, error, finished
 *
 * Every provider here drives a locally installed CLI, so the shared helpers
 * below are the CLI-shaped ones: quoting, folding history down to a prompt,
 * and summarising tool arguments for the activity rows.
 */
QtObject {
    id: root

    // Called once the process exits. Return { finished: true } to force-close the message.
    function onFinished(message): var {
        return {};
    }

    // Clear any per-request state held on the strategy.
    function reset() {}

    /**
     * Shell command printing how much of the account's quota is left, or "" when the CLI
     * cannot say. Run on its own, never as part of a turn.
     */
    function usageCommand(): string {
        return "";
    }

    /**
     * Decodes that output into `[{ label, remaining, resets }]`, where `remaining` is a
     * percentage *left*. The CLIs disagree on almost everything here — one prints
     * columns of percent remaining, the other prose in percent used — so each
     * normalises its own, and the UI only ever sees the one convention.
     */
    function parseUsage(text): var {
        return [];
    }

    /* ---------- Shared helpers -------------------------------------------- */

    function shellQuote(text): string {
        return `'${String(text).replace(/'/g, "'\\''")}'`;
    }

    /**
     * Folds history into alternating user/assistant turns. `rawContent` is what
     * gets sent and already carries any attachment paths; `content` is the
     * display form. See ConduitService.sendUserMessage.
     */
    function collapseRoles(messages): var {
        let out = [];
        for (const message of messages) {
            const text = (message.rawContent && message.rawContent.length > 0) ? message.rawContent : message.content;
            if (!text || text.length === 0) continue;
            if (out.length > 0 && out[out.length - 1].role === message.role) {
                out[out.length - 1].content += "\n\n" + text;
                continue;
            }
            out.push({ "role": message.role, "content": text });
        }
        // A turn has to start from the user.
        while (out.length > 0 && out[0].role !== "user") out.shift();
        return out;
    }

    // Expects the output of collapseRoles, whose `content` is already the raw form.
    function lastUserText(messages): string {
        for (let i = messages.length - 1; i >= 0; i--) {
            if (messages[i].role === "user") return messages[i].content;
        }
        return "";
    }

    // No session to resume yet, so replay the conversation as a labelled transcript.
    function renderConversation(messages): string {
        if (messages.length === 1) return messages[0].content;
        const transcript = messages.map(message => `${message.role === "user" ? "User" : "Assistant"}: ${message.content}`).join("\n\n");
        return `Continue the following conversation. Reply only with the assistant's next turn.\n\n${transcript}`;
    }

    /**
     * Condenses a tool's arguments into one line for the activity row. The two
     * CLIs disagree on casing — claude sends `file_path`, agy sends `AbsolutePath`
     * — so both spellings are checked before falling back to the first key.
     */
    function summarizeToolInput(name, input): string {
        if (!input || typeof input !== "object") return "";
        const preferred = ["file_path", "path", "pattern", "command", "url", "query", "prompt", "description",
            "AbsolutePath", "TargetFile", "CommandLine", "Pattern", "Query", "SearchDirectory", "Url", "Instruction"];
        for (const key of preferred) {
            if (input[key]) return String(input[key]).split("\n")[0].slice(0, 200);
        }
        const keys = Object.keys(input);
        return keys.length > 0 ? `${keys[0]}: ${String(input[keys[0]]).split("\n")[0].slice(0, 160)}` : "";
    }
}
