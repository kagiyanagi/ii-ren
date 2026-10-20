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

    /** Ask every agent again, as the page opens. */
    function refresh(): void {
        root.agents.forEach(agent => agent.refresh());
        root.antigravity.checkLatest();
        root.whisperProbe.running = true;
    }
}
