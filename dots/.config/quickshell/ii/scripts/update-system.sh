#!/usr/bin/env bash
# Upgrades the system with whichever package manager it has. The "update" action
# (Config.options.apps.update) runs this in a terminal.
if command -v pacman >/dev/null; then pkexec pacman -Syu
elif command -v dnf >/dev/null; then pkexec dnf upgrade --refresh
elif command -v emerge >/dev/null; then pkexec emerge --ask --update --deep --newuse @world
else echo "No pacman, dnf or emerge here: update with your distribution's own tool."
fi
