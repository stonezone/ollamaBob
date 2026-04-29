import SwiftUI

/// Live phosphor-green android. Replaces the static `bob_*.png` sprite pack
/// with a SwiftUI vector drawing whose mood is a blend of layered shapes:
/// rounded antenna head, two-LED eyes, scan-line mouth. Idle: 3.5s breath
/// loop + occasional eye-LED flicker. Mood expressions retarget the LEDs
/// (color/shape) and the mouth scan line.
struct ClassicRobotCharacterView: View {

    let expression: BobPersonaExpression
    let palette: BobPersonaPalette
    let gaze: CGPoint?
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breath: CGFloat = 1.0
    @State private var ledFlicker: Double = 1.0

    var body: some View {
        ZStack {
            antenna
            head
            eyes
            mouth
        }
        .frame(width: size, height: size * 1.05)
        .scaleEffect(breath)
        .onAppear { startIdleLoop() }
        .onChange(of: expression.mood) { _, _ in startIdleLoop() }
        .accessibilityElement()
        .accessibilityLabel("Classic Robot")
        .accessibilityValue(expression.mood.rawValue)
    }

    // MARK: - Layers

    private var antenna: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(palette.accentColor)
                .frame(width: size * 0.10, height: size * 0.10)
                .opacity(antennaTipOpacity)
            Rectangle()
                .fill(palette.glyphStroke)
                .frame(width: size * 0.04, height: size * 0.14)
        }
        .offset(y: -size * 0.46)
    }

    private var head: some View {
        RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        palette.characterBaseHues.first ?? palette.accentColor.opacity(0.35),
                        (palette.characterBaseHues.dropFirst().first ?? palette.accentColor).opacity(0.85)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .stroke(palette.glyphStroke.opacity(0.55), lineWidth: 1.2)
            }
            .shadow(color: palette.accentColor.opacity(0.35), radius: size * 0.08, x: 0, y: size * 0.03)
            .frame(width: size * 0.78, height: size * 0.72)
    }

    private var eyes: some View {
        let yOffset = -size * 0.04 + gazeOffset.height
        return HStack(spacing: size * 0.12) {
            led
            led
        }
        .offset(x: gazeOffset.width, y: yOffset)
    }

    private var led: some View {
        Circle()
            .fill(eyeColor)
            .overlay(Circle().stroke(palette.glyphStroke.opacity(0.6), lineWidth: 0.8))
            .frame(width: size * 0.14, height: size * 0.14)
            .opacity(ledOpacity)
            .shadow(color: eyeColor.opacity(0.7), radius: size * 0.04)
    }

    private var mouth: some View {
        // Scan-line mouth — a horizontal pill that lengthens for `.speaking`
        // and `.happy`, contracts for `.sheepish` and `.confused`.
        Capsule()
            .fill(palette.accentColor)
            .frame(width: mouthWidth, height: size * 0.04)
            .offset(y: size * 0.20)
            .opacity(0.85)
    }

    // MARK: - Mood-driven values

    private var eyeColor: Color {
        switch expression.mood {
        case .error, .confused:     return BobColors.Signal.danger
        case .naughty:              return BobColors.Signal.warn
        case .listening, .speaking: return palette.accentColor
        case .happy:                return palette.accentColor.opacity(0.95)
        case .sheepish:             return palette.accentColor.opacity(0.7)
        default:                    return palette.accentColor
        }
    }

    private var ledOpacity: Double {
        switch expression.mood {
        case .thinking:     return 0.55 * ledFlicker
        case .sheepish:     return 0.5
        case .idle:         return 0.85 * ledFlicker
        default:            return 0.95
        }
    }

    private var mouthWidth: CGFloat {
        let base = size * 0.30
        switch expression.mood {
        case .speaking:     return base * 1.3
        case .happy:        return base * 1.15
        case .sheepish:     return base * 0.55
        case .confused:     return base * 0.4
        case .error:        return base * 0.5
        default:            return base
        }
    }

    private var antennaTipOpacity: Double {
        switch expression.mood {
        case .thinking, .listening: return 0.5 + 0.5 * ledFlicker
        case .speaking, .happy:     return 1.0
        case .error:                return 0.9
        default:                    return 0.75
        }
    }

    private var gazeOffset: CGSize {
        guard let gaze else { return .zero }
        // Gaze point is normalized 0...1 inside the rendering frame; map to
        // a ±size*0.04 LED offset so the eyes track without escaping the head.
        let dx = (gaze.x - 0.5) * size * 0.08
        let dy = (gaze.y - 0.5) * size * 0.06
        return CGSize(width: dx, height: dy)
    }

    // MARK: - Animation

    private func startIdleLoop() {
        guard !reduceMotion else {
            breath = 1.0
            ledFlicker = 1.0
            return
        }
        withAnimation(BobMotion.breath) {
            breath = 1.025
        }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            ledFlicker = expression.mood == .thinking ? 0.3 : 0.85
        }
    }
}
