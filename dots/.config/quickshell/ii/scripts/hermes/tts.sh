#!/usr/bin/env bash
# Runs scripts/hermes/tts.py inside the Hermes agent's own interpreter, with the
# agent checkout as cwd so its imports resolve. Mirrors gateway.sh's resolution
# on purpose rather than sharing it: gateway.sh is load-bearing for the whole
# Hermes page and is not touched for a sibling feature.
set -euo pipefail

hermes_home="${HERMES_HOME:-$HOME/.hermes}"
agent_dir="$hermes_home/hermes-agent"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -d $agent_dir ]] || { echo '{"ok":false,"paths":[],"error":"hermes-agent not found"}'; exit 127; }

if [[ -x $agent_dir/venv/bin/python ]]; then
    python_bin="$agent_dir/venv/bin/python"
elif [[ -x $agent_dir/.venv/bin/python ]]; then
    python_bin="$agent_dir/.venv/bin/python"
else
    python_bin="$(command -v python3 || true)"
    [[ -n $python_bin ]] || { echo '{"ok":false,"paths":[],"error":"no python for hermes-agent"}'; exit 127; }
fi

cd "$agent_dir"
unset PYTHONPATH PYTHONHOME
export HERMES_HOME="$hermes_home"
exec "$python_bin" "$here/tts.py" "$@"
