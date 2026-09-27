#!/usr/bin/env bash
# Launches the Hermes stdio JSON-RPC gateway (tui_gateway.entry) for the sidebar.
#
# Hermes ships no CLI subcommand for the stdio gateway -- the desktop app and
# hermes' own scripts/probe_active_session_exclusivity.py both invoke the module
# directly, so this does the same. The agent must run with its own interpreter
# and its checkout as cwd; the `hermes` launcher in PATH unsets PYTHONPATH/HOME
# for the same reason.
#
# `-u` is required: buffered stdout would hold streamed deltas until a turn ends.

set -euo pipefail

# A remote gateway (HERMES_GATEWAY_SSH=user@host, from the desktop app's
# connections.json) is this same script run on that host: stdio JSON-RPC goes over
# ssh unchanged, and the remote HERMES_HOME brings its own sessions, memory and
# personality. The script is sent as the command, so nothing has to be installed
# there but hermes-agent. BatchMode: there is no terminal to type a password into,
# and a prompt would hang the sidebar on "Starting".
# ponytail: assumes the remote login shell is bash ($'...' quoting from %q).
if [[ -n ${HERMES_GATEWAY_SSH:-} ]]; then
    key="${HERMES_GATEWAY_SSH_KEY:-}"
    key="${key/#\~/$HOME}"
    ssh_args=(-T -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3)
    [[ -n $key ]] && ssh_args+=(-i "$key")
    exec ssh "${ssh_args[@]}" -- "$HERMES_GATEWAY_SSH" "bash -c $(printf '%q' "$(<"$0")") gateway.sh"
fi

# The sidebar's toolsets: the configured `platform_toolsets.cli` list minus
# computer_use, which cannot work on this machine. cua-driver drives X11 only
# (XSendEvent + AT-SPI); under Hyprland its window discovery returns an empty
# list, so `list_windows` says 0 windows and `capture` fails. It is also a
# deferred tool, so the agent spent two extra round trips discovering it before
# finding that out -- measured on 2026-09-21, ~40s before the first real action.
# Everything else stays: dropping toolsets would make the sidebar worse at the
# tasks that are not desktop control.
#
# tools/check-hermes-desktop.py asserts this stays in sync with config.yaml.
: "${HERMES_TUI_TOOLSETS:=a2a,browser,clarify,code_execution,connections,context_engine,cronjob,delegation,file,image_gen,memory,session_search,skills,terminal,todo,tts,video,video_gen,vision,web,yuanbao}"
export HERMES_TUI_TOOLSETS

# HERMES_HOME is where config/sessions live; the agent checkout sits under it.
hermes_home="${HERMES_HOME:-$HOME/.hermes}"
agent_dir="$hermes_home/hermes-agent"

if [[ ! -d $agent_dir ]]; then
    echo "hermes-agent not found at $agent_dir" >&2
    exit 127
fi

# The checkout is only where the interpreter has to start (see the cd below), not
# the user's workspace. Left to os.getcwd(), a newer agent reads its own source
# tree as the project: the coding posture ("You are a coding agent pairing with the
# user inside their codebase") and the checkout's AGENTS.md go in after SOUL.md,
# and a 66k-character prompt buried the persona -- the Pi answered as a generic
# coding assistant. TERMINAL_CWD is what both the terminal tool and that detection read.
export TERMINAL_CWD="${TERMINAL_CWD:-$HOME}"

# Prefer the agent's own venv; fall back to uv, then a bare python3 that can at
# least produce a real import error instead of a silent exit.
if [[ -x $agent_dir/venv/bin/python ]]; then
    python_bin="$agent_dir/venv/bin/python"
elif [[ -x $agent_dir/.venv/bin/python ]]; then
    python_bin="$agent_dir/.venv/bin/python"
elif command -v uv >/dev/null 2>&1; then
    cd "$agent_dir"
    exec uv run --active --no-sync python -u -m tui_gateway.entry "$@"
else
    python_bin="$(command -v python3 || true)"
    [[ -n $python_bin ]] || { echo "no python interpreter for hermes-agent" >&2; exit 127; }
fi

# A `utils/` or `agent/` directory in the launch dir would shadow the agent's own
# top-level modules, so the checkout must be cwd -- hermes_bootstrap hardens the
# rest of sys.path from there.
cd "$agent_dir"
unset PYTHONPATH PYTHONHOME
export HERMES_HOME="$hermes_home"
exec "$python_bin" -u -m tui_gateway.entry "$@"
