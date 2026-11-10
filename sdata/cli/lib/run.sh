#!/usr/bin/env bash

# Command: iiren run
echo -e "${BLUE}Killing Quickshell & Reloading Hyprland...${NC}"

# By config, not name: a Nix install runs as .quickshell-wra
qs kill -c ii
hyprctl reload

sleep 1.0

bash "${BASH_SOURCE[0]%/*}/start-shell.sh" || return $?
echo -e "${GREEN}✓ Quickshell started${NC}"
