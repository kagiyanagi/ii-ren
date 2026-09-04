#!/usr/bin/env python3
import json
import os
import shutil
import subprocess

def query_cursor():
    theme = ""
    size = 24

    # 1. Try gsettings (GTK / GNOME interface)
    if shutil.which("gsettings"):
        try:
            t = subprocess.check_output(
                ["gsettings", "get", "org.gnome.desktop.interface", "cursor-theme"],
                stderr=subprocess.DEVNULL
            ).decode().strip().strip("'\"")
            if t:
                theme = t
            s = subprocess.check_output(
                ["gsettings", "get", "org.gnome.desktop.interface", "cursor-size"],
                stderr=subprocess.DEVNULL
            ).decode().strip()
            if s.isdigit():
                size = int(s)
        except Exception:
            pass

    # 2. Try KDE kreadconfig6 if gsettings did not provide values
    if (not theme or size == 24) and shutil.which("kreadconfig6"):
        try:
            if not theme:
                t = subprocess.check_output(
                    ["kreadconfig6", "--file", "kdeglobals", "--group", "Mouse", "--key", "cursorTheme"],
                    stderr=subprocess.DEVNULL
                ).decode().strip()
                if t:
                    theme = t
            s = subprocess.check_output(
                ["kreadconfig6", "--file", "kdeglobals", "--group", "Mouse", "--key", "cursorSize"],
                stderr=subprocess.DEVNULL
            ).decode().strip()
            if s.isdigit():
                size = int(s)
        except Exception:
            pass

    # 3. Try xsettingsd config if still not found
    xsettings_conf = os.path.expanduser("~/.config/xsettingsd/xsettingsd.conf")
    if os.path.isfile(xsettings_conf):
        try:
            with open(xsettings_conf, "r") as f:
                for line in f:
                    line = line.strip()
                    if not theme and line.startswith("Gtk/CursorThemeName"):
                        parts = line.split(maxsplit=1)
                        if len(parts) == 2:
                            theme = parts[1].strip("'\"")
                    elif size == 24 and line.startswith("Gtk/CursorThemeSize"):
                        parts = line.split(maxsplit=1)
                        if len(parts) == 2 and parts[1].isdigit():
                            size = int(parts[1])
        except Exception:
            pass

    return {"theme": theme or "Bibata-Modern-Classic", "size": size}

if __name__ == "__main__":
    print(json.dumps(query_cursor()))
