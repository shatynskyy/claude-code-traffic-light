import Foundation
import Combine

/// One live Claude Code session's status.
struct SessionInfo: Identifiable, Equatable {
    let id: String
    let state: LightState
    let title: String
    let ts: Int
}

/// Watches `~/.claude/status/` (one JSON file per Claude Code session, written
/// by the hooks) and publishes an aggregate `LightState` plus the per-session
/// list. Aggregation priority: waiting (red) > working (yellow) > done (green).
@MainActor
final class StatusStore: ObservableObject {
    static let shared = StatusStore()

    @Published private(set) var state: LightState = .idle
    @Published private(set) var sessions: [SessionInfo] = []

    private let dir = FileManager.default
        .homeDirectoryForCurrentUser.appendingPathComponent(".claude/status")

    private var pollTimer: Timer?
    private var pendingWaiting: DispatchWorkItem?
    private let transcripts = TranscriptReader()

    /// A "waiting" (red) aggregate only surfaces if it lasts longer than this,
    /// so normal tool execution (which fires PreToolUse→waiting) doesn't flash
    /// red — only a real Allow/Deny prompt, which you take seconds to answer.
    private let waitingDebounce: TimeInterval = 1.0

    /// Sessions with no update for longer than this are treated as dead
    /// (covers crashes / killed terminals where SessionEnd never fired).
    private let staleAfter: TimeInterval = 1800 // 30 min

    /// Yellow (working) can get stuck if you interrupt Claude (no Stop hook
    /// fires). Clear it only once the session is truly idle: no hook AND the
    /// transcript has been quiet this long. Red (waiting) is intentionally left
    /// as-is — a real Allow/Deny prompt must stay red until resolved.
    private let workingDecay: TimeInterval = 60

    /// Trust the transcript's interrupt marker only after the session has been
    /// quiet this long — avoids a race where a just-submitted prompt fires
    /// `working` before the new prompt is written to the transcript (which would
    /// briefly still show the previous "[Request interrupted]" as the last line).
    private let interruptGrace: TimeInterval = 5

    private init() {
        recompute()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recompute() }
        }
    }

    private func recompute() {
        let now = Date().timeIntervalSince1970
        var list: [SessionInfo] = []

        if let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                guard
                    let data = try? Data(contentsOf: file),
                    let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let raw = obj["state"] as? String,
                    var st = LightState(rawValue: raw),
                    let ts = obj["ts"] as? Int,
                    now - Double(ts) <= staleAfter
                else { continue }

                let transcript = obj["transcript"] as? String
                let (tTitle, interrupted) = transcripts.read(transcript)

                // Yellow can get stuck when you interrupt Claude (no Stop hook).
                // Clear it instantly if the transcript shows the interrupt marker,
                // otherwise fall back to "idle for a while". Red (waiting) is left
                // as-is on purpose — a real Allow/Deny must stay red.
                let age = now - Double(ts)
                if st == .working {
                    if interrupted, age > interruptGrace {
                        st = .done
                    } else if age > workingDecay,
                              transcriptIdle(transcript, now: now, longerThan: workingDecay) {
                        st = .done
                    }
                }

                let cwd = (obj["cwd"] as? String) ?? ""
                let folder = cwd.isEmpty ? "session" : (cwd as NSString).lastPathComponent
                let title = (tTitle?.isEmpty == false) ? tTitle! : folder
                let sid = (obj["session"] as? String) ?? file.deletingPathExtension().lastPathComponent
                list.append(SessionInfo(id: sid, state: st, title: title, ts: ts))
            }
        }

        list.sort { a, b in
            if rank(a.state) != rank(b.state) { return rank(a.state) < rank(b.state) }
            return a.ts > b.ts
        }
        if list != sessions { sessions = list }

        let aggregate: LightState
        if list.contains(where: { $0.state == .waiting }) { aggregate = .waiting }
        else if list.contains(where: { $0.state == .working }) { aggregate = .working }
        else if list.contains(where: { $0.state == .done }) { aggregate = .done }
        else { aggregate = .idle }
        apply(aggregate)
    }

    private func rank(_ s: LightState) -> Int {
        switch s {
        case .waiting: return 0
        case .working: return 1
        case .done:    return 2
        case .idle:    return 3
        }
    }

    /// True if the session's transcript hasn't been written for `seconds`
    /// (or we have no transcript path) — i.e. Claude isn't actively producing.
    private func transcriptIdle(_ path: String?, now: TimeInterval, longerThan seconds: TimeInterval) -> Bool {
        guard let path, !path.isEmpty,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970
        else { return true }
        return now - mtime > seconds
    }

    private func apply(_ newState: LightState) {
        if newState == .waiting {
            guard state != .waiting, pendingWaiting == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.state = .waiting
                self?.pendingWaiting = nil
            }
            pendingWaiting = work
            DispatchQueue.main.asyncAfter(deadline: .now() + waitingDebounce, execute: work)
        } else {
            pendingWaiting?.cancel()
            pendingWaiting = nil
            if state != newState { state = newState }
        }
    }
}
