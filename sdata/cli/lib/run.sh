#!/usr/bin/env bash

# Command: iiren run
echo -e "${BLUE}Killing Quickshell & Reloading Hyprland...${NC}"

# By config, not name: a Nix install runs as .quickshell-wra
qs kill -c ii
hyprctl reload

sleep 1.0

# Do not pass an Electron host's Node mode to apps launched by the shell.
nohup env -u ELECTRON_RUN_AS_NODE qs -c ii > /dev/null 2>&1 &
echo -e "${GREEN}✓ Quickshell started${NC}"
