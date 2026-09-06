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

# HERMES_HOME is where config/sessions live; the agent checkout sits under it.
hermes_home="${HERMES_HOME:-$HOME/.hermes}"
agent_dir="$hermes_home/hermes-agent"

if [[ ! -d $agent_dir ]]; then
    echo "hermes-agent not found at $agent_dir" >&2
    exit 127
fi

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
