#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source $(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate
# Deliberately not exec: leaving python a grandchild means a shell reload,
# which terminates this wrapper, does not take a running bake with it. A video
# bake is minutes of work and there is no resume. Cancelling one on purpose
# goes through the pid in the status file instead - see the shell service.
"$SCRIPT_DIR/subject_cutout.py" "$@"
EXIT_CODE=$?
deactivate

exit $EXIT_CODE
