#!/usr/bin/env bash

# Print installed model names as a compact JSON array
ollama list | tail -n +2 | awk '{print $1}' | jq -R . | jq -sc .
