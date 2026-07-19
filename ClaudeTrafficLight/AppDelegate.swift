import SwiftUI
import AppKit
import Combine

/// Owns the always-on-top floating desktop panel that shows the traffic light.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var hosting: NSHostingView<DesktopWidget>?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = StatusStore.shared // begin watching the status file
        makePanel()

        // Resize the panel whenever the user picks a new widget size.
        WidgetSettings.shared.$size
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.applySize() }
            }
            .store(in: &cancellables)

        // Show/hide the panel when toggled from the menu.
        WidgetSettings.shared.$isVisible
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                guard let panel = self?.panel else { return }
                if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
            }
            .store(in: &cancellables)
    }

    private func makePanel() {
        let host = NSHostingView(rootView: DesktopWidget())
        host.setFrameSize(host.fittingSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.contentView = host
        panel.setContentSize(host.fittingSize)

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameTopLeftPoint(
                NSPoint(x: visible.maxX - panel.frame.width - 24, y: visible.maxY - 24)
            )
        }

        panel.orderFrontRegardless()
        self.panel = panel
        self.hosting = host
    }

    /// Re-fit the panel to the hosting view after the widget size changes,
    /// keeping the top-left corner anchored so it doesn't drift.
    private func applySize() {
        guard let panel, let hosting else { return }
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        hosting.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.fittingSize)
        panel.setFrameTopLeftPoint(topLeft)
    }

}
