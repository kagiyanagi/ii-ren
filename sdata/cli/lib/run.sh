#!/usr/bin/env bash

# Command: iiren run
echo -e "${BLUE}Killing Quickshell & Reloading Hyprland...${NC}"

# By config, not name: a Nix install runs as .quickshell-wra
qs kill -c ii
hyprctl reload

sleep 1.0

nohup qs -c ii > /dev/null 2>&1 &
echo -e "${GREEN}✓ Quickshell started${NC}"
