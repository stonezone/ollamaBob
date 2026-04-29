import SwiftUI

/// Abstract Bob mark for HUD + popover + menu-bar surfaces.
/// Persona-tinted via `tint` (Phase 2 will route this through `Persona.palette`).
/// Animates per `state`: breath (idle), spiral (thinking), bloom (speaking),
/// pulse (listening), hairline ring (alert).
struct GlassGlyph: View {
    enum State {
        case idle
        case thinking
        case listening
        case speaking
        case alert
    }

    let state: State
    let tint: Color
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @SwiftUI.State private var breathPhase: CGFloat = 1.0
    @SwiftUI.State private var thinkRotation: Double = 0
    @SwiftUI.State private var listenPulse: CGFloat = 1.0

    init(state: State = .idle, tint: Color = BobColors.Accent.bobBlue, size: CGFloat = 28) {
        self.state = state
        self.tint = tint
        self.size = size
    }

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)

        ZStack {
            tile
                .fill(reduceTransparency ? tint.opacity(0.22) : Color.white.opacity(0.10))
                .background {
                    if !reduceTransparency, #available(macOS 26.0, *) {
                        tile.fill(.clear).glassEffect(.regular.tint(tint.opacity(0.55)), in: tile)
                    } else if !reduceTransparency {
                        tile.fill(.ultraThinMaterial)
                    }
                }
                .overlay(tile.strokeBorder(BobColors.Glass.strokeHighlight, lineWidth: 0.6))

            innerMark
        }
        .frame(width: size, height: size)
        .scaleEffect(currentScale)
        .rotationEffect(.degrees(state == .thinking ? thinkRotation : 0))
        .animation(animation(for: state), value: breathPhase)
        .animation(animation(for: state), value: thinkRotation)
        .animation(animation(for: state), value: listenPulse)
        .onAppear { startAnimating() }
        .onChange(of: state) { _, _ in startAnimating() }
        .accessibilityElement()
        .accessibilityLabel("Bob")
        .accessibilityValue(stateLabel)
    }

    private var innerMark: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.white, tint.opacity(0.85), tint],
                    center: .init(x: 0.35, y: 0.30),
                    startRadius: 0,
                    endRadius: size * 0.45
                )
            )
            .frame(width: size * 0.42, height: size * 0.42)
            .shadow(color: tint.opacity(0.55), radius: state == .speaking ? size * 0.25 : size * 0.15)
    }

    private var currentScale: CGFloat {
        switch state {
        case .idle, .alert:     return breathPhase
        case .thinking:         return 0.96
        case .listening:        return listenPulse
        case .speaking:         return 1.05
        }
    }

    private var stateLabel: String {
        switch state {
        case .idle:         return "idle"
        case .thinking:     return "thinking"
        case .listening:    return "listening"
        case .speaking:     return "speaking"
        case .alert:        return "needs attention"
        }
    }

    private func animation(for state: State) -> Animation? {
        if reduceMotion { return BobMotion.respectingReduceMotion(BobMotion.responsive, reduceMotion: true) }
        switch state {
        case .idle, .alert:     return BobMotion.breath
        case .thinking:         return .linear(duration: 2.4).repeatForever(autoreverses: false)
        case .listening:        return .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
        case .speaking:         return BobMotion.expressive
        }
    }

    private func startAnimating() {
        guard !reduceMotion else { return }
        switch state {
        case .idle, .alert:
            breathPhase = 1.04
        case .thinking:
            thinkRotation = 360
        case .listening:
            listenPulse = 1.08
        case .speaking:
            breathPhase = 1.05
        }
    }
}
