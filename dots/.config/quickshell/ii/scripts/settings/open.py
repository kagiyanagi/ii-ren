#!/usr/bin/env python3
"""Present the settings app, launching it once if its IPC is not ready yet."""
import fcntl
import hashlib
import os
import subprocess
import sys
import time
from pathlib import Path


def main():
    settings = str(Path(sys.argv[1]).resolve())
    page = sys.argv[2] if len(sys.argv) > 2 else ""
    highlight = sys.argv[3] if len(sys.argv) > 3 else ""
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/ii-settings-{os.getuid()}")
    runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
    key = hashlib.sha256(settings.encode()).hexdigest()[:16]
    command = ["qs", "ipc", "-p", settings, "call", "settings", "open", page, highlight]

    def present():
        try:
            return subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5).returncode == 0
        except subprocess.TimeoutExpired:
            return False

    # A cold start needs time to register IPC. Serialize launches through that
    # interval; no-duplicate also covers an app launched outside this helper.
    with (runtime / f"ii-settings-{key}.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if present():
            return 0
        env = dict(os.environ, II_SETTINGS_PAGE=page, II_SETTINGS_HIGHLIGHT=highlight)
        for name in ("__QUICKSHELL_CRASH_INFO_FD", "__QUICKSHELL_CRASH_DUMP_PID", "__QUICKSHELL_CRASH_SIGNAL"):
            env.pop(name, None)
        with (runtime / f"ii-settings-{key}.log").open("w") as log:
            process = subprocess.Popen(["qs", "--no-duplicate", "-p", settings], env=env,
                                       stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if present():
                return 0
            if process.poll() not in (None, 0):
                break
            time.sleep(0.1)
    print("Settings did not register its IPC; see the ii-settings log in the runtime directory", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
