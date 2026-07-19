import SwiftUI

/// The four statuses the traffic light can show.
enum LightState: String, Codable, CaseIterable {
    case idle
    case working
    case waiting
    case done

    var title: String {
        switch self {
        case .idle:    return "Idle"
        case .working: return "Working"
        case .waiting: return "Needs input"
        case .done:    return "Done"
        }
    }

    /// Solid accent colour used for the menu-bar dot and the status pill.
    var accent: Color {
        switch self {
        case .idle:    return Color(white: 0.55)
        case .working: return Color(hex: 0xF6B400)
        case .waiting: return Color(hex: 0xE01B2E)
        case .done:    return Color(hex: 0x17B355)
        }
    }
}

/// One physical lamp in the housing.
enum LampRole {
    case red, yellow, green

    func isLit(for state: LightState) -> Bool {
        switch self {
        case .red:    return state == .waiting
        case .yellow: return state == .working
        case .green:  return state == .done
        }
    }

    /// Whether this lamp gently pulses while lit.
    var pulses: Bool { self == .red || self == .yellow }

    /// The red "needs input" lamp pulses faster to grab attention.
    var fastPulse: Bool { self == .red }

    /// Radial fill colours when the lamp is lit (light core → deep rim).
    var litColors: [Color] {
        switch self {
        case .red:    return [Color(hex: 0xFF8A8A), Color(hex: 0xE01B2E), Color(hex: 0x8F0A18)]
        case .yellow: return [Color(hex: 0xFFF0B0), Color(hex: 0xF6B400), Color(hex: 0xA86F00)]
        case .green:  return [Color(hex: 0xB6FFCF), Color(hex: 0x17B355), Color(hex: 0x0A6E34)]
        }
    }

    /// Colour of the glow cast around a lit lamp.
    var glow: Color {
        switch self {
        case .red:    return Color(hex: 0xFF2837)
        case .yellow: return Color(hex: 0xFFBE14)
        case .green:  return Color(hex: 0x1ED76E)
        }
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
