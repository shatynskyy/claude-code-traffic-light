import Foundation

/// Reads the tail of a Claude Code session transcript (`.jsonl`) to extract a
/// human-friendly title and whether the last turn was interrupted by the user.
/// Results are cached by file mtime, so the tail is only re-parsed when the
/// transcript actually changes.
///
/// Note: this reads Claude Code's internal transcript format, which is not a
/// stable API and may change between versions. If it does, callers fall back to
/// the folder name / a timeout.
final class TranscriptReader {
    private struct Cached { let mtime: TimeInterval; let title: String?; let interrupted: Bool }
    private var cache: [String: Cached] = [:]

    func read(_ path: String?) -> (title: String?, interrupted: Bool) {
        guard let path, !path.isEmpty,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970
        else { return (nil, false) }

        if let cached = cache[path], cached.mtime == mtime {
            return (cached.title, cached.interrupted)
        }
        let result = parse(path)
        cache[path] = Cached(mtime: mtime, title: result.title, interrupted: result.interrupted)
        return result
    }

    private func parse(_ path: String) -> (title: String?, interrupted: Bool) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return (nil, false) }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let tail: UInt64 = 262_144 // last 256 KB is plenty for the recent tail
        let start = size > tail ? size - tail : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return (nil, false) }

        var lines = text.split(separator: "\n").map(String.init)
        if start > 0, !lines.isEmpty { lines.removeFirst() } // drop possibly-partial first line

        var custom: String?, ai: String?, prompt: String?
        var lastRole: String?, lastText: String?

        for line in lines {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            else { continue }
            switch obj["type"] as? String {
            case "custom-title": if let t = obj["customTitle"] as? String, !t.isEmpty { custom = t }
            case "ai-title":     if let t = obj["aiTitle"] as? String, !t.isEmpty { ai = t }
            case "last-prompt":  if let t = obj["lastPrompt"] as? String, !t.isEmpty { prompt = t }
            case "user", "assistant":
                if let m = obj["message"] as? [String: Any], let role = m["role"] as? String {
                    lastRole = role
                    lastText = Self.text(from: m["content"])
                }
            default: break
            }
        }

        let title = custom ?? ai ?? prompt
        let interrupted = (lastRole == "user") && (lastText?.hasPrefix("[Request interrupted") ?? false)
        return (title, interrupted)
    }

    private static func text(from content: Any?) -> String? {
        if let s = content as? String { return s }
        if let arr = content as? [[String: Any]] {
            for item in arr where item["type"] as? String == "text" { return item["text"] as? String }
        }
        return nil
    }
}
