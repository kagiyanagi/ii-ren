import QtQuick

/**
 * The locally installed `claude` CLI, so this runs on your own Claude Code
 * account — no API key, no separate billing.
 *
 * The CLI's `--output-format stream-json` wraps the Anthropic streaming events
 * in an envelope:
 *
 *   {"type":"stream_event","event":{"type":"content_block_delta","delta":{...}}}
 *
 * so unwrapping `.event` and handing it to applySseEvent() covers text and
 * thinking. On top of that the CLI adds frames the raw API has no equivalent
 * for: session init, tool results, rate limits, and a terminal `result` frame
 * carrying cost.
 *
 * Deliberate choices:
 * - The script cd's into `request.workingDir`, which is what tools can reach.
 * - `--bare` is NOT used: its help states auth becomes strictly
 *   ANTHROPIC_API_KEY and that OAuth is never read, which would defeat the point.
 * - The prompt is read from a file, never interpolated into the command line.
 *
 * Limitations: the CLI exposes no temperature or max-tokens flag.
 */
ProviderStrategy {
    id: root

    function buildScript(request) {
        const messages = root.collapseRoles(request.messages);
        if (messages.length === 0) return { "error": "Nothing to send." };

        const resuming = (request.sessionId ?? "").length > 0;
        const prompt = resuming ? root.lastUserText(messages) : root.renderConversation(messages);
        if (prompt.length === 0) return { "error": "Nothing to send." };

        let args = ["--print", "--output-format stream-json", "--include-partial-messages", "--verbose", `--model ${root.shellQuote(request.modelId)}`];
        let systemPrompt = request.systemPrompt ?? "";

        if (request.enableTools) {
            // No approval UI exists in print mode, so permissions are decided up front.
            args.push(`--permission-mode ${root.shellQuote(request.permissionMode)}`);
            // Pasted images are decoded to a temp directory outside the working
            // directory, so tools have to be told they may read it.
            if ((request.attachDir ?? "").length > 0) {
                args.push(`--add-dir ${root.shellQuote(request.attachDir)}`);
            }
            if ((request.disallowedTools ?? "").length > 0) {
                args.push(`--disallowed-tools ${root.shellQuote(request.disallowedTools)}`);
            }
            if ((request.desktopMcp ?? "").length > 0) {
                // Inline, per launch: the user's own MCP servers keep loading from their
                // config, and the shell's server never has to be written into it. (agy has
                // no equivalent flag and takes it from `agy mcp add` instead.)
                const mcp = JSON.stringify({ mcpServers: { desktop: { command: "python3", args: [request.desktopMcp] } } });
                args.push(`--mcp-config ${root.shellQuote(mcp)}`);
                // Only bypassPermissions approves everything by itself, and in print mode an
                // approval prompt is a denial, so the server is allow-listed by name.
                args.push("--allowed-tools mcp__desktop");
            }
        } else {
            args.push("--tools ''");
            // Without this the model narrates tool calls it cannot make ("I'll fetch
            // that page. WebFetch(...)") and then has to walk it back, which reads as
            // a broken integration rather than a disabled one.
            systemPrompt += "\n\nYou have NO tools in this session: no file access, no shell, no web search or fetch. Never write out, simulate, or promise a tool call. If something needs a tool, say plainly in one sentence that you cannot do it here and that the user can enable tools with /tools on.";
        }

        if (resuming) {
            args.push(`--resume ${root.shellQuote(request.sessionId)}`);
        } else if (systemPrompt.trim().length > 0) {
            args.push(`--append-system-prompt ${root.shellQuote(systemPrompt)}`);
        }

        // Reported through the same channel as a real reply, so the failure surfaces
        // in the transcript instead of only in the shell log.
        const failure = JSON.stringify({
            "type": "result",
            "is_error": true,
            "result": `Working directory not found: ${request.workingDir}`
        });

        const script = "#!/usr/bin/env bash\n"
            + 'export PATH="$HOME/.local/bin:$PATH"\n' // Quickshell's PATH may lack ~/.local/bin
            + `cd ${root.shellQuote(request.workingDir)} || { printf '%s\\n' ${root.shellQuote(failure)}; exit 1; }\n`
            // exec matters: `bash script.sh` does NOT implicitly exec its last command
            // (unlike `bash -c`), so without this the shell owns claude as a child and
            // stopping signals only the shell — leaving the agent running, tools and all.
            + `exec claude ${args.join(" ")} < ${root.shellQuote(request.payloadPath)}\n`;

        return { "script": script, "payload": prompt };
    }

    function usageCommand() {
        return 'export PATH="$HOME/.local/bin:$PATH"; exec claude --print /usage';
    }

    /**
     * Prose, in percent *used*:
     *
     *   Current session: 21% used · resets Aug 22, 7:20pm (Asia/Kolkata)
     *   Current week (all models): 16% used · resets Aug 27, 11:30am (Asia/Kolkata)
     *
     * Inverted to percent remaining here. The rest of the report — the breakdown of what
     * is driving usage — simply never matches. The reset time is taken by searching for
     * the word rather than by matching the separator, which is a middle dot.
     */
    function parseUsage(text) {
        let out = [];
        for (const line of String(text).split("\n")) {
            const match = line.match(/^\s*(.+?):\s*(\d+)\s*%\s*used\b/);
            if (!match) continue;

            const marker = line.indexOf("resets");
            const resets = marker < 0 ? ""
                : line.slice(marker + 6).replace(/\s*\([^)]*\)\s*$/, "").trim();

            const label = match[1]
                .replace(/^Current\s+/i, "")
                .replace(/\s*\(all models\)/i, "")
                .trim();

            out.push({
                "label": label.charAt(0).toUpperCase() + label.slice(1),
                "remaining": Math.max(0, 100 - parseInt(match[2], 10)),
                "resets": resets
            });
        }
        return out;
    }

    function parseLine(line, message) {
        const clean = line.trim();
        if (clean.length === 0 || !clean.startsWith("{")) return {};

        let frame;
        try {
            frame = JSON.parse(clean);
        } catch (e) {
            console.log("[Conduit] claude: unparseable line:", clean.slice(0, 200));
            return {};
        }

        // Streaming text and thinking: the same events as the HTTP API, one envelope deeper.
        if (frame.type === "stream_event" && frame.event) {
            return root.applySseEvent(frame.event);
        }

        // Session id, so the next turn can --resume instead of replaying the transcript.
        if (frame.type === "system" && frame.subtype === "init") {
            return frame.session_id ? { "sessionId": frame.session_id } : {};
        }

        // Authoritative tool arguments. content_block_start announces the tool with an
        // empty input and streams it as input_json_delta fragments; this frame carries
        // the assembled object, so it's the sane place to read arguments from.
        if (frame.type === "assistant") {
            let calls = [];
            for (const block of frame.message?.content ?? []) {
                if (block.type !== "tool_use") continue;
                calls.push({
                    "id": block.id,
                    "name": block.name,
                    "input": root.summarizeToolInput(block.name, block.input)
                });
            }
            return calls.length > 0 ? { "toolCalls": calls } : {};
        }

        // Tool results arrive as a synthetic user turn.
        if (frame.type === "user") {
            let results = [];
            for (const block of frame.message?.content ?? []) {
                if (block.type !== "tool_result") continue;
                let text = block.content;
                if (Array.isArray(text)) {
                    text = text.map(entry => entry?.text ?? "").join("\n");
                }
                results.push({
                    "id": block.tool_use_id,
                    "content": String(text ?? ""),
                    "failed": block.is_error === true
                });
            }
            return results.length > 0 ? { "toolResults": results } : {};
        }

        if (frame.type === "rate_limit_event") {
            const info = frame.rate_limit_info ?? {};
            return { "rateLimit": { "status": info.status ?? "", "resetsAt": info.resetsAt ?? 0, "kind": info.rateLimitType ?? "" } };
        }

        // Terminal frame: authoritative usage, cost, and error state.
        if (frame.type === "result") {
            let result = { "finished": true };
            if (frame.is_error) {
                result.error = frame.result ?? frame.api_error_status ?? "The claude CLI reported an error.";
            }
            if (frame.total_cost_usd !== undefined) result.cost = frame.total_cost_usd;
            if (frame.usage) {
                result.tokenUsage = {
                    input: (frame.usage.input_tokens ?? 0) + (frame.usage.cache_creation_input_tokens ?? 0) + (frame.usage.cache_read_input_tokens ?? 0),
                    output: frame.usage.output_tokens ?? -1
                };
            }
            return result;
        }

        return {};
    }

    /**
     * Decodes one Anthropic streaming event into a delta. Split out from parseLine
     * because the CLI wraps these same events in an envelope rather than inventing
     * its own text format.
     */
    function applySseEvent(event) {
        if (event.type === "error" || event.error) {
            return { "error": event.error?.message ?? JSON.stringify(event.error ?? event), "finished": true };
        }

        if (event.type === "message_start") {
            const usage = event.message?.usage;
            if (usage) {
                return { "tokenUsage": { input: usage.input_tokens ?? -1, output: usage.output_tokens ?? -1 } };
            }
            return {};
        }

        // A new block means a new part: text after a tool call must not be appended
        // to the text that preceded it.
        if (event.type === "content_block_start") {
            const block = event.content_block ?? {};
            if (block.type === "tool_use") {
                return { "toolStart": { "id": block.id, "name": block.name } };
            }
            return { "newBlock": block.type === "thinking" ? "thinking" : "text" };
        }

        if (event.type === "content_block_delta") {
            const delta = event.delta ?? {};
            if (delta.type === "text_delta" && delta.text) return { "textDelta": delta.text };
            if (delta.type === "thinking_delta" && delta.thinking) return { "thinkingDelta": delta.thinking };
            return {};
        }

        if (event.type === "message_delta") {
            if (event.usage) return { "tokenUsage": { output: event.usage.output_tokens ?? -1 } };
            return {};
        }

        if (event.type === "message_stop") return { "finished": true };

        return {};
    }
}
