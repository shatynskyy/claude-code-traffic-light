#!/bin/bash
# Installs the status writer and wires up Claude Code hooks so the widget
# reflects the current session state. Safe to re-run (it de-duplicates itself).
set -e

CLAUDE_DIR="$HOME/.claude"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$CLAUDE_DIR"
cp "$SRC_DIR/traffic-light.sh" "$CLAUDE_DIR/traffic-light.sh"
chmod +x "$CLAUDE_DIR/traffic-light.sh"

python3 - "$CLAUDE_DIR/settings.json" <<'PY'
import json, os, sys

path = sys.argv[1]
cmd = os.path.expanduser("~/.claude/traffic-light.sh")

data = {}
if os.path.exists(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        data = {}

hooks = data.setdefault("hooks", {})
# Lifecycle event -> state the widget should show.
#   working -> yellow   waiting -> red   done -> green   end -> remove session
mapping = {
    "UserPromptSubmit": "working",
    "PreToolUse":       "waiting",
    "PostToolUse":      "working",
    "Notification":     "waiting",
    "Stop":             "done",
    "SessionEnd":       "end",
}

for event, state in mapping.items():
    groups = hooks.setdefault(event, [])
    # drop any previously-installed traffic-light hook before re-adding
    groups = [g for g in groups
              if not any(cmd in h.get("command", "") for h in g.get("hooks", []))]
    groups.append({"hooks": [{"type": "command", "command": f"{cmd} {state}"}]})
    hooks[event] = groups

with open(path, "w") as f:
    json.dump(data, f, indent=2)

print("Updated", path)
PY

echo "Done. Fully restart your Claude Code session so the hooks take effect."
