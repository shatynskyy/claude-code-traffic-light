#!/bin/bash
# Removes everything install-hooks.sh created: the traffic-light hook entries
# (other hooks are left untouched), the writer script, and all status files.
set -e

CLAUDE_DIR="$HOME/.claude"

python3 - "$CLAUDE_DIR/settings.json" <<'PY'
import json, os, shutil, sys

path = sys.argv[1]
if not os.path.exists(path):
    print("No settings.json — nothing to clean there.")
else:
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        sys.exit(f"ERROR: {path} is not valid JSON — fix or remove it, then re-run. Nothing was changed.")
    shutil.copyfile(path, path + ".backup")

    hooks = data.get("hooks", {})
    for event in list(hooks.keys()):
        groups = hooks[event]
        kept = [g for g in groups
                if not any("traffic-light.sh" in h.get("command", "")
                           for h in g.get("hooks", []))]
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    if not hooks:
        data.pop("hooks", None)

    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    print("Removed traffic-light hooks from", path)
PY

rm -f "$CLAUDE_DIR/traffic-light.sh"
rm -rf "$CLAUDE_DIR/status"
rm -f "$CLAUDE_DIR/traffic-light-state.json"

echo "Done. Fully restart Claude Code. You can now delete the app."
