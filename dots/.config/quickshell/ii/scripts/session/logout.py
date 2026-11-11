#!/usr/bin/env python3
"""Ask windows to close, leaving the session alive if an app refuses."""
import json
import re
import subprocess
import time


def clients():
    reply = subprocess.run(["hyprctl", "-j", "clients"], capture_output=True, text=True, check=True)
    windows = json.loads(reply.stdout)
    if not isinstance(windows, list):
        raise ValueError("Invalid client list")
    return [window for window in windows if window.get("mapped", True)]


def logout():
    try:
        windows = clients()
        for window in windows:
            address = window.get("address", "")
            if not re.fullmatch(r"0x[0-9a-fA-F]+", address):
                raise ValueError("Invalid window address")
            # A protocol close lets the app save or ask the user about unsaved work.
            subprocess.run(["hyprctl", "dispatch",
                            f'hl.dsp.window.close({{window = "address:{address}"}})'], check=True)

        # An unsaved-work dialog or a refused close keeps the desktop alive.
        # Bound the wait so canceling a dialog cannot log out much later when
        # the user happens to close their last window.
        deadline = time.monotonic() + 30
        while clients():
            if time.monotonic() >= deadline:
                subprocess.run(["notify-send", "Logout canceled", "Some windows are still open."])
                return 1
            time.sleep(0.1)
        subprocess.run(["hyprctl", "dispatch", "hl.dsp.exit()"], check=True)
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Logout canceled: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(logout())
