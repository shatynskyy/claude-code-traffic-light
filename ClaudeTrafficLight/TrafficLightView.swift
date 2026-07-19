import SwiftUI

/// A single lamp: a recessed bezel ring with a lens that lights up and glows.
struct LampView: View {
    let role: LampRole
    let state: LightState

    @State private var pulsing = false

    private var lit: Bool { role.isLit(for: state) }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: 0x202226), Color(hex: 0x303338), Color(hex: 0x16181B)],
                        center: UnitPoint(x: 0.5, y: 0.42),
                        startRadius: 22,
                        endRadius: 48
                    )
                )

            Circle()
                .fill(lensGradient)
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1.5))
                .overlay(highlight, alignment: .topLeading)
                .padding(9)
                .shadow(color: lit ? role.glow.opacity(0.75) : .clear, radius: lit ? 16 : 0)
                .shadow(color: lit ? role.glow.opacity(0.45) : .clear, radius: lit ? 34 : 0)
        }
        .frame(width: 92, height: 92)
        .scaleEffect(pulsing ? 1.03 : 1.0)
        .onAppear { syncPulse() }
        .onChange(of: state) { _, _ in syncPulse() }
    }

    private var lensGradient: RadialGradient {
        RadialGradient(
            colors: lit ? role.litColors : [Color(white: 0.14), Color(white: 0.04)],
            center: UnitPoint(x: 0.5, y: 0.42),
            startRadius: 2,
            endRadius: 44
        )
    }

    private var highlight: some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.5), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 26, height: 17)
            .padding(.top, 14)
            .padding(.leading, 12)
            .opacity(lit ? 0.55 : 0.18)
    }

    private func syncPulse() {
        if lit && role.pulses {
            withAnimation(.easeInOut(duration: role.fastPulse ? 0.5 : 0.85).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { pulsing = false }
        }
    }
}

/// The full traffic-light housing with three lamps.
struct TrafficLightView: View {
    let state: LightState

    var body: some View {
        VStack(spacing: 12) {
            LampView(role: .red, state: state)
            LampView(role: .yellow, state: state)
            LampView(role: .green, state: state)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x4A4E54), Color(hex: 0x26282C), Color(hex: 0x1C1E21)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.black.opacity(0.5), lineWidth: 1)
                )
        )
        .overlay(alignment: .topLeading) { bolt.padding(10) }
        .overlay(alignment: .topTrailing) { bolt.padding(10) }
        .overlay(alignment: .bottomLeading) { bolt.padding(10) }
        .overlay(alignment: .bottomTrailing) { bolt.padding(10) }
        .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 18)
    }

    private var bolt: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color(hex: 0x6A6E74), Color(hex: 0x24262A)],
                    center: UnitPoint(x: 0.35, y: 0.3),
                    startRadius: 0,
                    endRadius: 5
                )
            )
            .frame(width: 8, height: 8)
    }
}

/// What the floating desktop panel shows: just the traffic light, sized by the
/// user's Small/Medium/Large choice.
struct DesktopWidget: View {
    @ObservedObject var store = StatusStore.shared
    @ObservedObject var settings = WidgetSettings.shared

    /// Natural (Large) bounds of `TrafficLightView`, used to size the scaled frame.
    private let base = CGSize(width: 128, height: 336)

    var body: some View {
        let scale = settings.size.scale
        TrafficLightView(state: store.state)
            .scaleEffect(scale, anchor: .center)
            .frame(width: base.width * scale, height: base.height * scale)
            .padding(34)
            .fixedSize()
    }
}
