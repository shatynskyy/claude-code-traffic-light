import Foundation

/// Installs the status-writer script and wires up Claude Code hooks in
/// `~/.claude/settings.json` — the same thing `scripts/install-hooks.sh` does,
/// but from inside the app so no terminal is needed.
enum HooksInstaller {
    private static let claudeDir = FileManager.default
        .homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    private static let scriptURL = claudeDir.appendingPathComponent("traffic-light.sh")
    private static let settingsURL = claudeDir.appendingPathComponent("settings.json")

    /// Which lifecycle event maps to which state (`end` removes the session).
    private static let mapping: [(event: String, state: String)] = [
        ("UserPromptSubmit", "working"),
        ("PreToolUse", "waiting"),
        ("PostToolUse", "working"),
        ("Stop", "done"),
        ("SessionEnd", "end"),
    ]

    private static let scriptBody = #"""
    #!/bin/bash
    # Writes per-session Claude Code status for the traffic-light widget.
    # Usage: traffic-light.sh <working|waiting|done|idle|end>
    # Claude Code passes the hook JSON (session_id, cwd, transcript_path) on stdin.
    STATE="${1:-idle}"
    DIR="$HOME/.claude/status"
    mkdir -p "$DIR"

    if [ -t 0 ]; then INPUT=""; else INPUT="$(cat)"; fi
    SID="$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    CWD="$(printf '%s' "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    TR="$(printf '%s' "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    [ -z "$SID" ] && SID="default"
    SAFE="$(printf '%s' "$SID" | tr -c 'A-Za-z0-9._-' '_')"
    [ -z "$SAFE" ] && SAFE="default"
    FILE="$DIR/$SAFE.json"

    if [ "$STATE" = "end" ]; then
      rm -f "$FILE"
      exit 0
    fi

    # Atomic write (tmp + rename) so the app never reads a truncated file.
    TMP="$FILE.$$.tmp"
    printf '{"state":"%s","ts":%s,"cwd":"%s","session":"%s","transcript":"%s"}\n' \
      "$STATE" "$(date +%s)" "$CWD" "$SID" "$TR" > "$TMP" && mv "$TMP" "$FILE"

    """#

    enum InstallError: LocalizedError {
        case malformedSettings
        var errorDescription: String? {
            "~/.claude/settings.json is not valid JSON — fix or remove it, then retry. Nothing was changed."
        }
    }

    static var isInstalled: Bool {
        guard FileManager.default.fileExists(atPath: scriptURL.path),
              let data = try? Data(contentsOf: settingsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"]
        else { return false }
        let dump = (try? JSONSerialization.data(withJSONObject: hooks))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return dump.contains("traffic-light.sh")
    }

    static func install() throws {
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        // If settings.json exists but is unreadable, REFUSE rather than silently
        // rewriting it with hooks only (that would wipe the user's config).
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL) {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InstallError.malformedSettings
            }
            root = json
            // Keep a restore point before we modify the file.
            let backupURL = claudeDir.appendingPathComponent("settings.json.backup")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: settingsURL, to: backupURL)
        }

        try scriptBody.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        let cmd = scriptURL.path

        for (event, state) in mapping {
            var groups = (hooks[event] as? [[String: Any]]) ?? []
            groups = groups.filter { group in
                let inner = (group["hooks"] as? [[String: Any]]) ?? []
                return !inner.contains { ($0["command"] as? String)?.contains("traffic-light.sh") ?? false }
            }
            groups.append(["hooks": [["type": "command", "command": "\(cmd) \(state)"]]])
            hooks[event] = groups
        }
        root["hooks"] = hooks

        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
        try out.write(to: settingsURL, options: .atomic)
    }

    /// Removes everything the installer created: our hook entries (other hooks
    /// are left untouched), the writer script, and all status files.
    static func uninstall() throws {
        if let data = try? Data(contentsOf: settingsURL) {
            guard var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InstallError.malformedSettings
            }
            let backupURL = claudeDir.appendingPathComponent("settings.json.backup")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: settingsURL, to: backupURL)

            if var hooks = root["hooks"] as? [String: Any] {
                for (event, value) in hooks {
                    guard let groups = value as? [[String: Any]] else { continue }
                    let kept = groups.filter { group in
                        let inner = (group["hooks"] as? [[String: Any]]) ?? []
                        return !inner.contains { ($0["command"] as? String)?.contains("traffic-light.sh") ?? false }
                    }
                    if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
                }
                if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
            }
            let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
            try out.write(to: settingsURL, options: .atomic)
        }
        try? FileManager.default.removeItem(at: scriptURL)
        try? FileManager.default.removeItem(at: claudeDir.appendingPathComponent("status"))
        try? FileManager.default.removeItem(at: claudeDir.appendingPathComponent("traffic-light-state.json"))
    }
}
