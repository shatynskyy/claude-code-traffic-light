import SwiftUI
import AppKit

/// Menu-bar icon: the Claude sunburst mark with a small status-coloured badge.
struct MenuBarLabel: View {
    @ObservedObject var store = StatusStore.shared

    var body: some View {
        Image(nsImage: Self.icon(status: store.state.accent))
    }

    /// The real Claude menu-bar (tray) template icon, loaded from the installed
    /// Claude app at runtime (not bundled). Falls back to a drawn sunburst.
    private static let claudeTray: NSImage? = {
        let dir = "/Applications/Claude.app/Contents/Resources/"
        for name in ["TrayIconTemplate@3x.png", "TrayIconTemplate@2x.png", "TrayIconTemplate.png"] {
            if let img = NSImage(contentsOfFile: dir + name) { return img }
        }
        return nil
    }()

    static func icon(status: Color) -> NSImage {
        let side: CGFloat = 18
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let foreground = isDark ? NSColor.white : NSColor.black

        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let full = NSRect(x: 0, y: 0, width: side, height: side)
            if let tray = Self.claudeTray {
                // Draw Claude's own tray mark, slightly enlarged (its template has
                // built-in padding), recoloured for the menu bar.
                let f: CGFloat = 1.32
                let markRect = NSRect(x: side * (1 - f) / 2, y: side * (1 - f) / 2,
                                      width: side * f, height: side * f)
                tray.draw(in: markRect)
                NSGraphicsContext.current?.compositingOperation = .sourceAtop
                foreground.setFill()
                NSBezierPath(rect: full).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            } else {
                drawSunburst(in: full, color: foreground)
            }

            // Status badge in the bottom-right corner.
            let r: CGFloat = 4.4
            let cx = side - r - 0.2, cy = r + 0.2
            let ball = NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
            NSColor(status).setFill()
            NSBezierPath(ovalIn: ball).fill()
            let ring = NSBezierPath(ovalIn: ball)
            ring.lineWidth = 1
            (isDark ? NSColor.black : NSColor.white).withAlphaComponent(0.6).setStroke()
            ring.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Claude-style sunburst: 12 round-tipped rays.
    private static func drawSunburst(in rect: NSRect, color: NSColor) {
        let cx = rect.midX, cy = rect.midY
        let inner = rect.width * 0.10
        let outer = rect.width * 0.46
        color.setStroke()
        for i in 0..<12 {
            let a = CGFloat(i) * (.pi * 2 / 12)
            let ray = NSBezierPath()
            ray.move(to: NSPoint(x: cx + cos(a) * inner, y: cy + sin(a) * inner))
            ray.line(to: NSPoint(x: cx + cos(a) * outer, y: cy + sin(a) * outer))
            ray.lineWidth = 1.6
            ray.lineCapStyle = .round
            ray.stroke()
        }
    }
}

/// Content of the menu-bar dropdown.
struct MenuContent: View {
    @ObservedObject var store = StatusStore.shared
    @ObservedObject var settings = WidgetSettings.shared
    @State private var hooksInstalled = HooksInstaller.isInstalled
    @State private var hooksNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(store.state.accent).frame(width: 11, height: 11)
                Text(store.state.title).font(.headline)
            }

            HStack(spacing: 10) {
                miniLamp(.red)
                miniLamp(.yellow)
                miniLamp(.green)
            }

            Divider()

            Picker("Size", selection: $settings.size) {
                ForEach(WidgetSize.allCases) { size in
                    Text(size.label).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                .toggleStyle(.checkbox)

            Divider()

            Button(hooksInstalled ? "Reinstall Hooks" : "Install Hooks") {
                installHooks()
            }
            if let hooksNote {
                Text(hooksNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button(settings.isVisible ? "Hide Widget" : "Show Widget") {
                settings.isVisible.toggle()
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 240)
    }

    private func installHooks() {
        do {
            try HooksInstaller.install()
            hooksInstalled = true
            hooksNote = "Installed — fully restart Claude Code."
        } catch {
            hooksNote = "Failed: \(error.localizedDescription)"
        }
    }

    private func miniLamp(_ role: LampRole) -> some View {
        let lit = role.isLit(for: store.state)
        return Circle()
            .fill(lit ? role.glow : Color(white: 0.28))
            .frame(width: 16, height: 16)
            .shadow(color: lit ? role.glow.opacity(0.8) : .clear, radius: 5)
    }
}
