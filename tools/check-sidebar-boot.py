#!/usr/bin/env python3
"""Nothing in the left sidebar runs at shell start: not its pages, not the agent, not
even the look for which agents are installed. All of it waits for the first open; after
that, `keepLeftSidebarLoaded` and the user decide.

Booting with it all built cost the RAM of every page and, once the page started its
agent, 280-770 MB more for a chat nobody had opened. A boot looks the same either way,
so the handlers that run at shell start are lifted out of the QML and run under `node`
against a fresh boot: sidebar shut, kept loaded on, nothing probed.
"""
import json
import re
import subprocess
from pathlib import Path

II = Path(__file__).resolve().parent.parent / "dots/.config/quickshell/ii"
frame = (II / "modules/ii/sidebarPolicies/SidebarPolicies.qml").read_text()
page = (II / "modules/ii/sidebarPolicies/Agent.qml").read_text()
service = (II / "services/AgentService.qml").read_text()


def body(src, header):
    """The brace-balanced block after `header`."""
    start = src.index(header)
    i = src.index("{", start + len(header) - 1)
    depth = 0
    for j in range(i, len(src)):
        depth += {"{": 1, "}": -1}.get(src[j], 0)
        if depth == 0:
            return src[i + 1:j]
    raise AssertionError(f"unbalanced block after {header!r}")


def run(js):
    return json.loads(subprocess.run(["node", "-e", js], capture_output=True, text=True, check=True).stdout)


boot = run(f"""
const calls = [];
const Config = {{ options: {{ sidebar: {{ keepLeftSidebarLoaded: true }} }} }};
const GlobalStates = {{ policiesPanelOpen: false }};
const root = {{ ensureContent: () => calls.push("ensureContent"), releaseContent: () => calls.push("releaseContent") }};
(function () {{ {body(frame, "Component.onCompleted:")} }})();
(function () {{ {body(frame, "function onKeepLeftSidebarLoadedChanged()")} }})();
GlobalStates.policiesPanelOpen = true;
(function () {{ {body(frame, "function onPoliciesPanelOpenChanged()")} }})();
console.log(JSON.stringify(calls));""")
assert boot == ["ensureContent"], \
    f"SidebarPolicies: the pages are built only by the first open, not by shell start ({boot})"

started = run(f"""
const started = [];
const proc = name => ({{ get running() {{ return false; }}, set running(v) {{ if (v) started.push(name); }} }});
const backendProbe = proc("probe");
const bridgeProc = proc("bridge");
const Persistent = {{ states: {{ agent: {{ backend: "claude" }} }} }};
const root = {{
    backendsProbed: false, _startWhenProbed: false, missing: false, backend: null, starting: false, lastError: "",
    backends: [], knownBackends: [{{ id: "claude" }}, {{ id: "codex" }}],
}};
root.setBackend = function (id) {{ {body(service, "function setBackend(id: string): void")} }};
root.ensureStarted = function () {{ {body(service, "function ensureStarted(): void")} }};
root.setBackend("codex");
const beforeOpen = started.slice();
root.ensureStarted();
console.log(JSON.stringify({{ beforeOpen, chosen: Persistent.states.agent.backend, open: started, waiting: root._startWhenProbed }}));""")
assert started["beforeOpen"] == [], f"AgentService: a backend switched before the first open started {started['beforeOpen']}"
assert started["chosen"] == "codex", "AgentService: a backend switched before the first open is forgotten"
assert started["open"] == ["probe"] and started["waiting"], \
    "AgentService: the first start looks for the agents, then starts the one picked"

probe = re.search(r"id: backendProbe\s*\n\s*running: (\w+)", service)
assert probe and probe.group(1) == "false", "AgentService: the agent probe runs at shell start"
assert not re.search(r"running: true", re.sub(r"//.*", "", service)), \
    "AgentService: a process starts with the singleton, which is built at shell start"
assert "Component.onCompleted" not in service, "AgentService: work at singleton load is work at shell start"

starts = body(page, "function startBackends(): void").strip().splitlines()
assert starts[0].strip() == "if (!root.onScreen)" and starts[1].strip() == "return;", \
    "Agent.qml: the agent and read-aloud start only when the page is on screen"
assert "readonly property bool onScreen: root.QsWindow.window?.visible ?? false" in page, \
    "Agent.qml: on screen means its window is shown, not merely built"

print("check-sidebar-boot: ok")
