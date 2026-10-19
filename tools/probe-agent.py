#!/usr/bin/env python3
"""Drive the sidebar's agent connector against the real CLI, the way the shell does.

    python3 tools/probe-agent.py claude|codex [scenario ...]

Starts scripts/agent/bridge.py, plays the shell's side of the protocol and prints
every frame it gets back, one line each. Approvals are answered with --approve
(once|session|deny, default once) and questions with the first choice.

Scenarios (default: basic):
  basic       one short reply, streamed
  tool        manual approvals, then a command that has to be approved
  look        the desktop tools: list windows, take a screenshot
  ask         the agent asks a multiple-choice question (Claude: AskUserQuestion)
  stop        interrupt a long answer midway
  retry       answer, then retry it; then undo it
  history     list conversations, resume the newest, check it came back
  models      list the models, switch to the second and back
  effort      list the current model's effort levels, answer once on the lowest, restore
  compact     fold the conversation

Each scenario spends a little of the agent's plan; nothing here mocks it. This is
a probe to watch, not a gate -- tools/check-agent-bridge.py is the gate.
"""
import json
import os
import subprocess
import sys
import threading
import time
import queue

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRIDGE = os.path.join(ROOT, "dots/.config/quickshell/ii/scripts/agent/bridge.py")


class Shell:
    def __init__(self, backend: str, approve: str):
        self.approve = approve
        self.proc = subprocess.Popen([sys.executable, BRIDGE, backend], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, text=True, bufsize=1)
        self.frames = queue.Queue()
        self.n = 0
        threading.Thread(target=self._pump, daemon=True).start()
        threading.Thread(target=self._errors, daemon=True).start()

    def _pump(self):
        for line in self.proc.stdout:
            try:
                self.frames.put(json.loads(line))
            except ValueError:
                print("  !! non-JSON:", line.rstrip()[:200])
        self.frames.put(None)

    def _errors(self):
        for line in self.proc.stderr:
            print("  [stderr]", line.rstrip()[:240])

    def send(self, frame):
        self.proc.stdin.write(json.dumps(frame) + "\n")
        self.proc.stdin.flush()

    def call(self, method, params=None, timeout=120):
        self.n += 1
        rid = f"ii-{self.n}"
        self.send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params or {}})
        return self.until(lambda f: f.get("id") == rid and "method" not in f, timeout, label=method)

    def until(self, done, timeout=180, label=""):
        """Print frames until `done(frame)`; answer questions on the way. Returns that frame."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                frame = self.frames.get(timeout=max(0.1, deadline - time.monotonic()))
            except queue.Empty:
                break
            if frame is None:
                raise SystemExit(f"bridge exited ({self.proc.wait()}) while waiting for {label}")
            self.show(frame)
            if frame.get("method") in ("approval", "clarify"):
                self.answer(frame)
            if done(frame):
                return frame
        raise SystemExit(f"timed out waiting for {label}")

    def answer(self, frame):
        params = frame.get("params") or {}
        if frame["method"] == "approval":
            self.send({"jsonrpc": "2.0", "id": frame["id"], "result": {"choice": self.approve, "all": False}})
        elif params.get("questions"):
            for q in params["questions"]:
                self.call("clarify.lock", {"request_id": frame["id"], "question_id": q["qid"], "answer": (q.get("choices") or ["yes"])[0]})
        else:
            self.send({"jsonrpc": "2.0", "id": frame["id"], "result": {"answer": (params.get("choices") or ["yes"])[0]}})

    @staticmethod
    def show(frame):
        if frame.get("method") == "event":
            p = frame["params"]
            payload = p.get("payload") or {}
            if p["type"] == "message.delta":
                print(payload.get("text", ""), end="", flush=True)
                return
            print(f"\n  <{p['type']}> {json.dumps(payload, ensure_ascii=False)[:300]}")
        elif frame.get("method"):
            print(f"\n  ?? {frame['method']} {json.dumps(frame.get('params'), ensure_ascii=False)[:300]}")
        else:
            body = frame.get("error") or frame.get("result")
            print(f"\n  = {frame.get('id')} {'ERROR ' if frame.get('error') else ''}{json.dumps(body, ensure_ascii=False)[:300]}")

    def turn(self, text, timeout=240):
        self.call("prompt.submit", {"session_id": self.sid, "text": text})
        return self.until(self._turn_end, timeout, label="end of turn")

    @staticmethod
    def _turn_end(frame):
        if frame.get("method") != "event":
            return False
        p = frame["params"]
        return p["type"] == "error" or (p["type"] == "message.complete" and (p.get("payload") or {}).get("status") in ("complete", "interrupted"))


def main(argv):
    if len(argv) < 2 or argv[1] not in ("claude", "codex"):
        print(__doc__)
        return 2
    approve = "once"
    args = argv[2:]
    if "--approve" in args:
        i = args.index("--approve")
        approve = args[i + 1]
        del args[i:i + 2]
    scenarios = args or ["basic"]
    shell = Shell(argv[1], approve)
    shell.until(lambda f: f.get("method") == "event" and f["params"]["type"] == "ready", 120, "ready")
    created = shell.call("session.create")
    shell.sid = (created.get("result") or {}).get("session_id") or ""
    print(f"\n== session {shell.sid}")
    for name in scenarios:
        print(f"\n===== {name}")
        if name == "basic":
            shell.turn("Reply with exactly the word: pong")
        elif name == "tool":
            shell.call("config.set", {"key": "approvals.mode", "value": "manual", "session_id": shell.sid})
            shell.turn("Run the shell command `mkdir -p /tmp/ii-probe && date > /tmp/ii-probe/stamp && cat /tmp/ii-probe/stamp` and tell me its output. Use your shell tool, do not guess.")
            shell.call("config.set", {"key": "approvals.mode", "value": "smart", "session_id": shell.sid})
        elif name == "look":
            shell.turn("Use the desktop tools: list my windows, then take a screenshot and tell me in one sentence what is on screen.")
        elif name == "ask":
            hint = "your AskUserQuestion tool" if argv[1] == "claude" else "your request_user_input tool"
            shell.turn(f"Use {hint} to ask me which colour I prefer, with the options red and blue. Then reply with only the colour I picked.")
        elif name == "stop":
            shell.call("prompt.submit", {"session_id": shell.sid, "text": "Count slowly from 1 to 400, one number per line."})
            shell.until(lambda f: f.get("method") == "event" and f["params"]["type"] == "message.delta", 120, "first text")
            time.sleep(2)
            # Not call(): the interrupted end can arrive before the answer to the
            # interrupt itself, and call() would print it on the way past.
            shell.send({"jsonrpc": "2.0", "id": "ii-stop", "method": "session.interrupt", "params": {"session_id": shell.sid}})
            shell.until(shell._turn_end, 60, "interrupted end")
        elif name == "retry":
            shell.turn("Pick a random fruit and reply with only its name.")
            shell.call("session.retry", {"session_id": shell.sid})
            shell.until(shell._turn_end, 240, "retried turn")
            print("\n  undo ->", (shell.call("session.undo", {"session_id": shell.sid, "turns": 1}).get("result") or {}))
        elif name == "history":
            listed = shell.call("session.list", {"limit": 5})
            sessions = (listed.get("result") or {}).get("sessions") or []
            if sessions:
                resumed = shell.call("session.resume", {"session_id": sessions[0]["id"]})
                rows = (resumed.get("result") or {}).get("messages") or []
                print(f"\n  resumed {sessions[0]['id']}: {len(rows)} rows, roles {[r['role'] for r in rows][:12]}")
                shell.sid = (resumed.get("result") or {}).get("session_id") or shell.sid
        elif name == "models":
            options = (shell.call("model.options", {"session_id": shell.sid}).get("result") or {})
            models = (options.get("providers") or [{}])[0].get("models") or []
            print(f"\n  models: {models}  current: {options.get('model')}")
            if len(models) > 1:
                shell.call("model.set", {"session_id": shell.sid, "model": models[1]})
                shell.call("model.set", {"session_id": shell.sid, "model": options.get("model")})
        elif name == "effort":
            options = (shell.call("model.options", {"session_id": shell.sid}).get("result") or {})
            caps = (options.get("providers") or [{}])[0].get("capabilities") or {}
            levels = [e["id"] for e in (caps.get(options.get("model")) or {}).get("efforts") or []]
            print(f"\n  effort levels for {options.get('model')}: {levels}")
            if levels:
                low = next((l for l in levels if l != "default"), levels[0])
                shell.call("effort.set", {"session_id": shell.sid, "effort": low})
                shell.turn("Reply with exactly the word: pong")
                shell.call("effort.set", {"session_id": shell.sid, "effort": levels[0]})
        elif name == "compact":
            shell.turn("Say hello in five languages.")
            shell.call("session.compress", {"session_id": shell.sid}, timeout=600)
        else:
            print("unknown scenario", name)
    shell.proc.stdin.close()
    shell.proc.wait(timeout=20)
    print("\n== done")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
