import QtQuick

/**
 * The locally installed `agy` CLI (Google Antigravity), so this runs on your own
 * Antigravity login — no API key. It reaches Gemini, Claude and GPT-OSS models
 * through the one subscription.
 *
 * Wire format. Nothing like Anthropic's SSE: agy emits NDJSON where every frame
 * is a flat envelope naming its own body, plus a `conversation_id` sibling.
 *
 *   {"event":"step_update","conversation_id":"…","step_update":{…}}
 *
 * A turn is a numbered list of steps — `user_input`, `checkpoint`,
 * `agent_response`, `tool` — each seen first as ACTIVE and again as DONE or
 * ERROR. `agent_response` steps carry `text_delta` fragments that concatenate
 * exactly into the final response, so they can be appended as they arrive.
 *
 * Input goes the same way round: `--input-format stream-json` reads one NDJSON
 * message per line from stdin, which keeps the prompt out of argv. `--print`
 * insists on taking its value inline, so it is not usable here.
 *
 * Measured differences from the claude CLI, all of them reflected below:
 * - Reasoning is counted in `usage.thinking_tokens` but never streamed, so this
 *   provider has no thinking blocks to show.
 * - The result frame reports tokens, not a price.
 * - There is no flag that removes the toolset, and no per-tool deny flag.
 * - A tool needing approval is auto-denied in print mode, and that ends the
 *   whole turn with status ERROR rather than just failing the one call. Even
 *   `--mode accept-edits` leaves `run_command` needing approval.
 * - `--effort` is rejected alongside a model whose id already encodes an effort
 *   level (`gemini-3.1-pro-high`), which is nearly all of them, so it is unused
 *   and the model id carries that choice instead.
 */
ProviderStrategy {
    id: root

    // Print mode otherwise abandons the turn after five minutes, which a
    // tool-using agent reaches easily.
    readonly property string printTimeout: "60m"

    // Per-request state; cleared by reset() before each turn.
    property bool sawText: false
    property bool toolsEnabled: true

    function reset() {
        root.sawText = false;
    }

    /** agy has one flag for unattended running and a --mode for the softer stances. */
    function permissionArgs(mode): string {
        switch (mode) {
        case "acceptEdits":
            return "--mode accept-edits";
        case "plan":
            return "--mode plan";
        default:
            // bypassPermissions and dontAsk both mean "never stop to ask".
            return "--dangerously-skip-permissions";
        }
    }

    /** Flags the process is launched with; fixed for the life of that process. */
    function buildArgs(request): var {
        root.toolsEnabled = request.enableTools === true;

        let args = [
            "--input-format stream-json",
            "--output-format stream-json",
            `--print-timeout ${root.printTimeout}`,
            `--model ${root.shellQuote(request.modelId)}`
        ];

        if (request.enableTools) {
            // Nothing can answer an approval prompt in print mode, so permissions are
            // decided up front. Without this agy asks, is auto-denied, and the whole
            // turn aborts — not just the one tool call.
            args.push(root.permissionArgs(request.permissionMode));
            // Pasted images are decoded to a temp directory outside the working
            // directory, so tools have to be told they may read it.
            if ((request.attachDir ?? "").length > 0) {
                args.push(`--add-dir ${root.shellQuote(request.attachDir)}`);
            }
        }

        // Pick up the conversation a previous process left behind, so replacing one
        // does not lose the thread.
        if ((request.sessionId ?? "").length > 0) {
            args.push(`--conversation ${root.shellQuote(request.sessionId)}`);
        }

        return args;
    }

    /** Keeps agy's own MCP registry in step with the shell's desktop-control switch. */
    function desktopMcpLine(request): string {
        const path = request.desktopMcp ?? "";
        if (path.length === 0) return "agy mcp remove desktop >/dev/null 2>&1\n";
        return `agy mcp add desktop -- python3 ${root.shellQuote(path)} >/dev/null 2>&1\n`;
    }

    /**
     * How to launch the CLI. Roughly ten of the twelve seconds a turn takes is agy
     * getting to its first `init`, and one process serves every turn of the
     * conversation, so it reads turns from stdin and is given no prompt here.
     */
    function buildProcessScript(request): var {
        // Reported through the same channel as a real reply, so the failure surfaces
        // in the transcript instead of only in the shell log.
        const failure = JSON.stringify({
            "event": "result",
            "result": { "status": "ERROR", "error": `Working directory not found: ${request.workingDir}` }
        });

        const script = "#!/usr/bin/env bash\n"
            + 'export PATH="$HOME/.local/bin:$PATH"\n' // Quickshell's PATH may lack ~/.local/bin
            + `cd ${root.shellQuote(request.workingDir)} || { printf '%s\\n' ${root.shellQuote(failure)}; exit 1; }\n`
            // agy has no per-launch MCP flag, so its registry is the only way in. `add` is
            // an upsert and the whole call costs a few ms, which is nothing against the ten
            // seconds of startup below.
            + root.desktopMcpLine(request)
            // exec matters: `bash script.sh` does NOT implicitly exec its last command
            // (unlike `bash -c`), so without this the shell owns agy as a child and
            // stopping signals only the shell — leaving the agent running, tools and all.
            + `exec agy ${root.buildArgs(request).join(" ")}\n`;

        return { "script": script };
    }

    /** One turn, as the single NDJSON line the CLI reads from stdin. */
    function buildTurnPayload(request): var {
        const messages = root.collapseRoles(request.messages);
        if (messages.length === 0) return { "error": "Nothing to send." };

        // Set when the CLI's conversation already holds the earlier turns, whether it
        // is still the same process or one resumed by id, so only the new message is
        // needed. A warmed-up process has an id but an empty conversation, which is
        // exactly why this is not inferred from the id.
        const continuing = request.continuing === true;
        let prompt = continuing ? root.lastUserText(messages) : root.renderConversation(messages);
        if (prompt.length === 0) return { "error": "Nothing to send." };

        // No --append-system-prompt exists, so the system prompt rides in front of the
        // prompt itself. Once continuing, it is already back in the history.
        let preamble = continuing ? "" : (request.systemPrompt ?? "").trim();

        if (request.enableTools !== true) {
            // Steering is all that is available: with no tool-disabling flag, a tool
            // call that cannot get approval ends the turn instead of the reply.
            preamble += "\n\nTools are disabled for this session. Do not run shell commands, do not create or edit files, and do not browse. Read-only lookups are the only calls that will succeed, and anything needing approval will abort the whole turn. If something needs a tool, say plainly in one sentence that you cannot do it here and that the user can enable tools with /tools on.";
        }

        preamble = preamble.trim();
        if (preamble.length > 0) {
            prompt = `${preamble}\n\n---\n\n${prompt}`;
        }

        return {
            "payload": JSON.stringify({ "event": "user", "message": { "role": "user", "content": prompt } }) + "\n"
        };
    }

    function buildScript(request) {
        const turn = root.buildTurnPayload(request);
        if (turn.error) return turn;
        return { "script": root.buildProcessScript(request).script, "payload": turn.payload };
    }

    function usageCommand() {
        // --print insists on taking its value inline.
        return 'export PATH="$HOME/.local/bin:$PATH"; exec agy --print=/usage';
    }

    /**
     * Tab-separated, already in percent remaining — two model families against two
     * windows:
     *
     *   Gemini Models\tWeekly Limit Remaining\t99%\t2026-08-28T12:55:29Z
     *   Claude and GPT models\tFive Hour Limit Remaining\t100%\t2026-08-22T16:13:21Z
     */
    function parseUsage(text) {
        let out = [];
        for (const line of String(text).split("\n")) {
            const columns = line.split("\t");
            if (columns.length < 3) continue;

            const percent = columns[2].match(/(\d+)\s*%/);
            if (!percent) continue;

            const family = columns[0].replace(/\s*models?\s*$/i, "").trim();
            const window = columns[1].replace(/\s*limit\s*remaining\s*$/i, "").trim();

            out.push({
                "label": window.length > 0 ? `${family} · ${window}` : family,
                "remaining": parseInt(percent[1], 10),
                "resets": root.formatStamp(columns[3] ?? "")
            });
        }
        return out;
    }

    /** ISO 8601 into something short and local. */
    function formatStamp(stamp): string {
        const clean = String(stamp).trim();
        if (clean.length === 0) return "";
        const when = new Date(clean);
        if (isNaN(when.getTime())) return clean;
        return when.toLocaleString(Qt.locale(), "d MMM, h:mm ap");
    }

    function parseLine(line, message) {
        const clean = line.trim();
        if (clean.length === 0 || !clean.startsWith("{")) return {};

        let frame;
        try {
            frame = JSON.parse(clean);
        } catch (e) {
            console.log("[Conduit] agy: unparseable line:", clean.slice(0, 200));
            return {};
        }

        const kind = frame.event ?? "";
        if (kind.length === 0) return {};
        // Every frame names its own body after its event.
        const body = (frame[kind] && typeof frame[kind] === "object") ? frame[kind] : ({});

        // The conversation id, so the next turn resumes instead of replaying history.
        if (kind === "init") {
            return frame.conversation_id ? { "sessionId": frame.conversation_id } : {};
        }

        if (kind === "step_update") return root.applyStepUpdate(body);

        // Terminal frame: authoritative usage and error state.
        if (kind === "result") {
            let result = { "finished": true };
            if (body.usage) result.tokenUsage = root.readUsage(body.usage);

            if ((body.status ?? "") !== "" && body.status !== "SUCCESS") {
                const detail = root.describeError(body.error ?? `Antigravity reported ${body.status}.`);
                if (root.sawText) {
                    // The answer already arrived. agy ends the turn with status ERROR for a
                    // single bad tool call, and flagging the message would repaint a complete
                    // reply as a total failure, so this goes underneath it as a note instead.
                    result.textDelta = `\n\n---\n\n**Antigravity reported an error after replying:** ${detail}`;
                } else {
                    result.error = detail;
                }
            } else if (!root.sawText && (body.response ?? "").length > 0) {
                // Succeeded without streaming anything: show the response rather
                // than an empty turn.
                result.textDelta = body.response;
            }
            return result;
        }

        return {};
    }

    function applyStepUpdate(step): var {
        let result = {};
        if (step.usage) result.tokenUsage = root.readUsage(step.usage);

        const kind = step.step_type ?? "";

        if (kind === "agent_response") {
            if ((step.text_delta ?? "").length > 0) {
                root.sawText = true;
                result.textDelta = step.text_delta;
            }
            return result;
        }

        if (kind === "tool") {
            // Steps are identified by index; there is no per-call tool id.
            const id = `step-${step.step_index}`;
            const info = step.tool_info ?? ({});
            const name = step.tool_name ?? info.name ?? "tool";

            if (step.state === "ACTIVE") {
                // Unlike the Anthropic stream, arguments are complete on the first
                // frame, so the row never has to be filled in afterwards.
                result.toolCalls = [{ "id": id, "name": name, "input": root.summarizeToolInput(name, info.parameters) }];
                return result;
            }

            // agy sends no tool output, so a successful call has nothing to expand.
            const failed = step.state === "ERROR" || info.error !== undefined;
            result.toolResults = [{
                "id": id,
                "content": failed ? String(info.error?.message ?? info.error ?? "Tool failed.") : "",
                "failed": failed
            }];
            return result;
        }

        // user_input and checkpoint steps carry nothing to display.
        return result;
    }

    function readUsage(usage): var {
        const hasInput = usage.input_tokens !== undefined || usage.cache_read_tokens !== undefined;
        const hasOutput = usage.output_tokens !== undefined || usage.thinking_tokens !== undefined;
        return {
            // A cache read is still input the model was given.
            input: hasInput ? (usage.input_tokens ?? 0) + (usage.cache_read_tokens ?? 0) : -1,
            // Reasoning is billed as output even though it is never streamed.
            output: hasOutput ? (usage.output_tokens ?? 0) + (usage.thinking_tokens ?? 0) : -1
        };
    }

    /** A denied tool reads as a bare permission error; say what would fix it. */
    function describeError(text): string {
        const detail = String(text);
        if (root.toolsEnabled || detail.indexOf("permission") < 0) return detail;
        return `${detail}\n\nTools are off, so approval could not be granted and the turn stopped. Enable them with \`/tools on\`.`;
    }
}
