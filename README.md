# Claude Code Traffic Light

A tiny macOS widget that shows what Claude Code is doing right now as a traffic
light — floating on your desktop and mirrored in the menu bar.

| Colour | State | Meaning |
| --- | --- | --- |
| 🟡 Yellow | `working` | Claude is working (thinking, running tools) |
| 🔴 Red | `waiting` | Claude needs you — an **Allow/Deny** prompt or a **choose-an-option** question |
| 🟢 Green | `done` | Claude finished its turn |
| ⚪ Grey | `idle` | No active session |

## How it works

Claude Code can run shell commands on lifecycle **hooks**. This project wires a
tiny script (`traffic-light.sh`) to those hooks; the script writes the current
state to `~/.claude/status.json`, and the app watches that file and colours the
light.

```
Claude Code  ──(hook fires)──▶  traffic-light.sh  ──writes──▶  ~/.claude/status.json
                                                                      │
                                                        app watches file (FSEvents + poll)
                                                                      ▼
                                                        traffic light (desktop + menu bar)
```

Hook → state mapping:

| Hook | Fires when… | State |
| --- | --- | --- |
| `UserPromptSubmit` | you send a prompt | 🟡 working |
| `PreToolUse` | Claude is about to use a tool | 🔴 waiting* |
| `PostToolUse` | a tool finished | 🟡 working |
| `Stop` | Claude finished its turn | 🟢 done |
| `Notification` | Claude is idle-waiting for you | 🔴 waiting |

\* `PreToolUse` fires for **every** tool, but the app **debounces** it: red only
appears if the wait lasts longer than ~0.5 s. Fast auto-approved commands never
flash red — only real Allow/Deny prompts and questions (which block until you
act) turn the light red.

> Note: some Claude Code setups don't fire the `Notification` hook on Allow/Deny
> prompts, which is why the red state is driven by `PreToolUse` + debounce
> rather than `Notification`.

## Setup

### 1. Wire up the hooks

```bash
./scripts/install-hooks.sh
```

This copies `traffic-light.sh` into `~/.claude/` and merges the hooks into
`~/.claude/settings.json` (your existing hooks are preserved; re-running is
safe). **Fully restart your Claude Code session afterwards** — hooks are only
loaded at session start.

### 2. Build & run the app

Open `ClaudeTrafficLight.xcodeproj` in Xcode and press **Run** (⌘R).

> Tip: for everyday use, don't keep it running under the Xcode debugger — build
> once, then launch the built `.app` on its own (Product → Show Build Folder, or
> copy it to `/Applications`). Running under the debugger can freeze the UI.

The app is a menu-bar utility (no Dock icon). A floating traffic light appears
in the top-right; drag it anywhere. Click the menu-bar icon for a menu:

- **Size** — Small / Medium / Large
- **Launch at Login** — start the widget automatically after you log in
- **Show / Hide Widget** — toggle the desktop light
- **Quit**

## Installing (for people who just want to use it)

This app isn't code-signed with an Apple Developer ID, so the easiest and safest
path is to **build it yourself** (free):

1. Install Xcode.
2. Clone this repo.
3. Run `./scripts/install-hooks.sh` and restart Claude Code.
4. Open the project in Xcode and Run, then copy the built app to `/Applications`.

If a pre-built `.app` is provided in Releases, macOS Gatekeeper will flag it as
unsigned. To open it: right-click the app → **Open** → **Open**, or run
`xattr -dr com.apple.quarantine /path/to/ClaudeTrafficLight.app`.

## Notes

- The app is **not sandboxed** so it can read `~/.claude/status.json`.
- Multiple concurrent Claude Code sessions share one status file — the most
  recent event wins.
- Requires macOS 14+.
