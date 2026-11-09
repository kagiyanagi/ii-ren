#!/usr/bin/env python3
"""Reloading Hyprland must not grow XDG_DATA_DIRS.

hyprland/env.lua puts the flatpak and system data directories in front of the
inherited XDG_DATA_DIRS. Hyprland keeps what `hl.env` sets in its own environment,
so on a reload `os.getenv` returns last load's value and the prepend ran again: four
more entries per reload. A day in, the shell (and every app it launched) had
/usr/share 13 times, and each change to an app folder made the shell rescan every
copy -- 90% of a 114 MB log held in RAM. The login environment usually lists the
same four already, so even the first load doubled them.

Run env.lua under plain Lua, the way Hyprland does: `hl.env` writes the value that
the next run's `os.getenv` reads. Assert every run yields the same value, no
directory appears twice, the four come first, and whatever else the login
environment (or, without one, the Nix profiles) supplied survives in its order.
"""
import os
import pathlib
import subprocess
import tempfile

ENV_LUA = (pathlib.Path(__file__).resolve().parent.parent
           / "dots/.config/hypr/hyprland/env.lua")
HOME = "/home/test"
STANDARD = [f"{HOME}/.local/share/flatpak/exports/share", "/var/lib/flatpak/exports/share",
            "/usr/local/share", "/usr/share"]
NIX = [f"{HOME}/.nix-profile/share", "/run/current-system/sw/share"]
RELOADS = 6

HARNESS = r"""
local inherited = os.getenv("CHECK_INHERITED")
local existing = {}
for dir in (os.getenv("CHECK_EXISTING") or ""):gmatch("[^:]+") do existing[dir] = true end
local env = { HOME = "/home/test", USER = "test" }
if inherited ~= "<unset>" then env.XDG_DATA_DIRS = inherited end
os.getenv = function(key) return env[key] end
hl = { env = function(key, value) env[key] = value end }
is_file_exists = function(path) return existing[path] == true end
for _ = 1, tonumber(arg[2]) do
    dofile(arg[1])
    print(env.XDG_DATA_DIRS)
end
"""


def loads(inherited, existing=()):
    """XDG_DATA_DIRS after each of RELOADS consecutive loads of env.lua."""
    with tempfile.NamedTemporaryFile("w", suffix=".lua") as harness:
        harness.write(HARNESS)
        harness.flush()
        env = {"PATH": os.environ["PATH"], "CHECK_INHERITED": inherited,
               "CHECK_EXISTING": ":".join(existing)}
        out = subprocess.run(["lua", harness.name, str(ENV_LUA), str(RELOADS)], env=env,
                             capture_output=True, text=True, check=True).stdout
    return out.splitlines()


cases = {
    # This machine: the login environment (flatpak's profile.d) already lists all four.
    "login lists the four": (":".join(STANDARD), (), STANDARD),
    # Others' directories stay, after the four, in their order; a trailing slash is the same directory.
    "login adds its own": ("/opt/app/share:/usr/share/:/usr/local/share::/var/lib/snapd/desktop",
                           (), STANDARD + ["/opt/app/share", "/var/lib/snapd/desktop"]),
    # What a day of reloads left behind collapses back.
    "already bloated": (":".join(STANDARD * 13 + ["/opt/app/share"]), (), STANDARD + ["/opt/app/share"]),
    # No login environment (greetd, NixOS TTY): the Nix profiles that exist go in instead.
    "no login environment": ("<unset>", NIX, STANDARD + NIX),
    "empty login environment": ("", (), STANDARD),
}

for name, (inherited, existing, expected) in cases.items():
    values = loads(inherited, existing)
    assert len(values) == RELOADS, (name, values)
    assert len(set(values)) == 1, f"{name}: the value changes across reloads: {values}"
    dirs = values[0].split(":")
    assert len(dirs) == len(set(dirs)), f"{name}: a directory appears twice: {dirs}"
    assert dirs == expected, f"{name}: {dirs} != {expected}"

print(f"ok: XDG_DATA_DIRS holds each directory once and stays the same over {RELOADS} reloads")
