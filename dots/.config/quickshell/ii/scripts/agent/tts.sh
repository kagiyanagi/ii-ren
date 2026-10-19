#!/usr/bin/env bash
# Runs scripts/agent/tts.py with the shell's own venv, which carries edge-tts
# (sdata/uv/requirements.in). Exits 127 without one, which the sidebar reads as
# "read-aloud is not available" and hides its buttons for.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
venv="$(eval echo "${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}")"

[[ -x $venv/bin/python ]] || { echo "[tts-missing] no shell venv at $venv" >&2; exit 127; }
unset PYTHONPATH PYTHONHOME
exec "$venv/bin/python" -u "$here/tts.py" "$@"
