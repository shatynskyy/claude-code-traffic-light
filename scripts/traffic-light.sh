#!/bin/bash
# Writes per-session Claude Code status for the traffic-light widget.
# Usage: traffic-light.sh <working|waiting|done|idle|end>
# Claude Code passes the hook JSON (with session_id, cwd) on stdin.
STATE="${1:-idle}"
DIR="$HOME/.claude/status"
mkdir -p "$DIR"

if [ -t 0 ]; then INPUT=""; else INPUT="$(cat)"; fi
SID="$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
CWD="$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -z "$SID" ] && SID="default"
SAFE="$(printf '%s' "$SID" | tr -c 'A-Za-z0-9._-' '_')"
[ -z "$SAFE" ] && SAFE="default"
FILE="$DIR/$SAFE.json"

if [ "$STATE" = "end" ]; then
  rm -f "$FILE"
  exit 0
fi

printf '{"state":"%s","ts":%s,"cwd":"%s","session":"%s"}\n' "$STATE" "$(date +%s)" "$CWD" "$SID" > "$FILE"
