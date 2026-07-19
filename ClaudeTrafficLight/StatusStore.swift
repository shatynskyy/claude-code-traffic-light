import Foundation
import Combine

/// Watches `~/.claude/status.json` (written by Claude Code hooks) and publishes
/// the current `LightState`. Uses a filesystem event source with a polling
/// fallback so it survives the file being replaced or created after launch.
@MainActor
final class StatusStore: ObservableObject {
    static let shared = StatusStore()

    @Published private(set) var state: LightState = .idle

    private let url = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/status.json")

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var pollTimer: Timer?
    private var pendingWaiting: DispatchWorkItem?

    /// A "waiting" (red) state only surfaces if it lasts longer than this, so
    /// fast auto-approved commands don't flash red — only real Allow/Deny
    /// prompts and choose-an-option questions do.
    private let waitingDebounce: TimeInterval = 0.5

    private init() {
        read()
        startWatching()
        startPolling()
    }

    private func startWatching() {
        stopWatching()
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return } // file may not exist yet — polling will retry

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .global()
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            Task { @MainActor in
                self.read()
                if flags.contains(.delete) || flags.contains(.rename) {
                    self.startWatching() // reopen on atomic replace
                }
            }
        }
        src.setCancelHandler { [weak self] in
            guard let self, self.fd >= 0 else { return }
            close(self.fd)
            self.fd = -1
        }
        source = src
        src.resume()
    }

    private func stopWatching() {
        source?.cancel()
        source = nil
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.fd < 0 { self.startWatching() }
                self.read()
            }
        }
    }

    private func read() {
        guard let data = try? Data(contentsOf: url) else { return }
        struct Payload: Decodable { let state: String }
        guard
            let payload = try? JSONDecoder().decode(Payload.self, from: data),
            let newState = LightState(rawValue: payload.state)
        else { return }
        apply(newState)
    }

    private func apply(_ newState: LightState) {
        if newState == .waiting {
            // Debounce: surface red only if it persists (real prompt / question).
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
