#!/bin/bash
# Writes the current Claude Code status for the traffic-light widget.
# Usage: traffic-light.sh <working|waiting|done|idle>
STATE="${1:-idle}"
DIR="$HOME/.claude"
mkdir -p "$DIR"
printf '{"state":"%s","ts":%s}\n' "$STATE" "$(date +%s)" > "$DIR/status.json"
