pragma Singleton
import qs.services.agent
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Settings > Agent's view of the three agents: installed, signed in, and the
 * jobs that change that (services/agent/AgentSetupAgent.qml).
 *
 * The settings app's alone. The shell never touches it -- its sidebar has
 * AgentService, which reads the same config -- so nothing here runs until the
 * Agent page is opened.
 */
Singleton {
    id: root

    property AgentSetupAgent claude: AgentSetupAgent {
        agentId: "claude"
        label: "Claude Code"
    }
    property AgentSetupAgent codex: AgentSetupAgent {
        agentId: "codex"
        label: "Codex"
    }
    property AgentSetupAgent antigravity: AgentSetupAgent {
        agentId: "antigravity"
        label: "Antigravity"
    }
    readonly property var agents: [root.claude, root.codex, root.antigravity]

    // Dictation's whisper.cpp, looked for as services/agent/SpeechToText.qml does.
    property bool whisperInstalled: false
    property Process whisperProbe: Process {
        command: ["sh", "-c", "command -v whisper-cli || command -v whisper-cpp || command -v whisper"]
        stdout: StdioCollector {
            onStreamFinished: root.whisperInstalled = this.text.trim().length > 0
        }
    }

    // Local read-aloud's kokoro-onnx, in the shell's venv found as scripts/agent/tts.sh
    // finds it. A venv from before it was added has edge-tts only, until `iiren update`.
    property bool kokoroInstalled: false
    property Process kokoroProbe: Process {
        command: ["bash", "-c", 'venv="$(eval echo "${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}")"; '
            + 'exec "$venv/bin/python" -c "import importlib.util, sys; sys.exit(importlib.util.find_spec(\'kokoro_onnx\') is None)"']
        onExited: exitCode => root.kokoroInstalled = exitCode === 0
    }

    /** Ask every agent again, as the page opens. */
    function refresh(): void {
        root.agents.forEach(agent => agent.refresh());
        root.antigravity.checkLatest();
        root.whisperProbe.running = true;
        root.kokoroProbe.running = true;
    }
}
