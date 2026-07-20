import Foundation
import Combine

/// One live Claude Code session's status.
struct SessionInfo: Identifiable, Equatable {
    let id: String
    let state: LightState
    let project: String
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

    /// A "waiting" (red) aggregate only surfaces if it lasts longer than this,
    /// so fast auto-approved commands don't flash red.
    private let waitingDebounce: TimeInterval = 0.5

    /// Sessions with no update for longer than this are treated as dead
    /// (covers crashes / killed terminals where SessionEnd never fired).
    private let staleAfter: TimeInterval = 1800 // 30 min

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
                    let st = LightState(rawValue: raw),
                    let ts = obj["ts"] as? Int,
                    now - Double(ts) <= staleAfter
                else { continue }
                let cwd = (obj["cwd"] as? String) ?? ""
                let project = cwd.isEmpty ? "session" : (cwd as NSString).lastPathComponent
                let sid = (obj["session"] as? String) ?? file.deletingPathExtension().lastPathComponent
                list.append(SessionInfo(id: sid, state: st, project: project, ts: ts))
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
