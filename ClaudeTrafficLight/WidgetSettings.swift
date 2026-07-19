import SwiftUI
import Combine
import ServiceManagement

/// Desktop widget size options. `large` matches the original dimensions.
enum WidgetSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var scale: CGFloat {
        switch self {
        case .small:  return 0.6
        case .medium: return 0.8
        case .large:  return 1.0
        }
    }

    var label: String {
        switch self {
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        }
    }
}

/// User-adjustable widget settings, persisted in UserDefaults.
@MainActor
final class WidgetSettings: ObservableObject {
    static let shared = WidgetSettings()

    @Published var size: WidgetSize {
        didSet { UserDefaults.standard.set(size.rawValue, forKey: "widgetSize") }
    }

    @Published var isVisible: Bool = true

    /// Start the widget automatically at login (via SMAppService).
    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin {
                    if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
                } else {
                    if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                }
            } catch {
                print("Launch-at-login toggle failed: \(error)")
            }
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "widgetSize") ?? WidgetSize.large.rawValue
        size = WidgetSize(rawValue: raw) ?? .large
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }
}
