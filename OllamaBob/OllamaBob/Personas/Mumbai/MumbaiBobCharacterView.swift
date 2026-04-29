import SwiftUI

/// Live cartoon "Mumbai Bob" — cheerful warm-amber face with tracking eyes,
/// expressive mouth, and a hint of the signature blue polo. Replaces the
/// static `mumbai_*.png` sprite pack with composed SwiftUI shapes:
/// head (circle), hair cap, eyes (whites + tracking pupils), brows,
/// mouth, polo collar.
///
/// Idle motion: 3.5s breath loop + ~5s blinks + smoothed cursor gaze.
/// Mood expressions blend brow tilt + mouth curvature + eye width.
struct MumbaiBobCharacterView: View {

    let expression: BobPersonaExpression
    let palette: BobPersonaPalette
    let gaze: CGPoint?
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breath: CGFloat = 1.0
    @State private var blinkPhase: CGFloat = 1.0  // 1 = open, 0.05 = closed

    var body: some View {
        ZStack {
            poloCollar
            head
            hair
            eyes
            brows
            mouth
            cheeks
        }
        .frame(width: size, height: size * 1.10)
        .scaleEffect(breath)
        .onAppear { startIdleLoop() }
        .onChange(of: expression.mood) { _, _ in startIdleLoop() }
        .accessibilityElement()
        .accessibilityLabel("Mumbai Bob")
        .accessibilityValue(expression.mood.rawValue)
    }

    // MARK: - Layers

    private var head: some View {
        Circle()
            .fill(skinGradient)
            .overlay {
                Circle().stroke(palette.glyphStroke.opacity(0.35), lineWidth: 1.0)
            }
            .frame(width: size * 0.78, height: size * 0.78)
            .shadow(color: palette.accentColor.opacity(0.20), radius: size * 0.06, x: 0, y: size * 0.02)
    }

    private var hair: some View {
        // Asymmetric crescent across the top of the head — gives Mumbai
        // Bob his side-parted look without trying to render strands.
        HairCrescent()
            .fill(Color(red: 0.18, green: 0.10, blue: 0.06))
            .frame(width: size * 0.78, height: size * 0.78)
            .offset(y: -size * 0.005)
    }

    private var eyes: some View {
        HStack(spacing: size * 0.13) {
            eye
            eye
        }
        .offset(y: -size * 0.05)
    }

    private var eye: some View {
        ZStack {
            Capsule()
                .fill(Color.white)
                .frame(width: size * 0.13, height: size * 0.10 * blinkPhase)
            // Pupil tracks gaze
            Circle()
                .fill(Color(red: 0.22, green: 0.14, blue: 0.08))
                .frame(width: size * 0.05, height: size * 0.05 * blinkPhase)
                .offset(x: gazeOffset.width, y: gazeOffset.height)
        }
    }

    private var brows: some View {
        HStack(spacing: size * 0.16) {
            BrowShape(tilt: leftBrowTilt)
                .stroke(Color(red: 0.18, green: 0.10, blue: 0.06), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .frame(width: size * 0.13, height: size * 0.05)
            BrowShape(tilt: rightBrowTilt)
                .stroke(Color(red: 0.18, green: 0.10, blue: 0.06), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .frame(width: size * 0.13, height: size * 0.05)
        }
        .offset(y: -size * 0.13)
    }

    private var mouth: some View {
        MouthShape(curvature: mouthCurvature, openness: mouthOpenness)
            .stroke(Color(red: 0.32, green: 0.16, blue: 0.12),
                    style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            .frame(width: size * 0.30, height: size * 0.10)
            .offset(y: size * 0.12)
    }

    private var cheeks: some View {
        // Faint rosy circles for happy/sheepish; transparent otherwise.
        let visibility: Double = {
            switch expression.mood {
            case .happy, .sheepish:     return 0.55
            case .speaking, .listening: return 0.25
            default:                    return 0.0
            }
        }()
        return HStack(spacing: size * 0.30) {
            Circle().fill(BobColors.Signal.danger.opacity(visibility * 0.4))
                .frame(width: size * 0.10, height: size * 0.07)
            Circle().fill(BobColors.Signal.danger.opacity(visibility * 0.4))
                .frame(width: size * 0.10, height: size * 0.07)
        }
        .offset(y: size * 0.04)
        .blur(radius: size * 0.015)
    }

    private var poloCollar: some View {
        // Suggestion of a blue polo neckline at the bottom of the frame.
        PoloCollar()
            .fill(Color(red: 0.22, green: 0.42, blue: 0.78))
            .overlay {
                PoloCollar().stroke(Color(red: 0.16, green: 0.30, blue: 0.58), lineWidth: 1.0)
            }
            .frame(width: size * 0.78, height: size * 0.30)
            .offset(y: size * 0.42)
    }

    // MARK: - Mood-driven values

    private var skinGradient: LinearGradient {
        let base = palette.characterBaseHues.first ?? BobColors.Persona.mumbaiAmber
        let highlight = palette.characterBaseHues.dropFirst().first ?? base.opacity(0.85)
        return LinearGradient(
            colors: [highlight, base],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var mouthCurvature: CGFloat {
        switch expression.mood {
        case .happy:        return 1.0
        case .speaking:     return 0.4
        case .sheepish:     return 0.2
        case .confused:     return -0.4
        case .error:        return -0.6
        case .thinking:     return 0.0
        case .listening:    return 0.15
        case .typing:       return 0.3
        case .naughty:      return 0.7
        case .idle:         return 0.25
        }
    }

    private var mouthOpenness: CGFloat {
        switch expression.mood {
        case .speaking:     return 0.7
        case .happy:        return 0.4
        case .confused:     return 0.3
        case .error:        return 0.5
        default:            return 0.05
        }
    }

    private var leftBrowTilt: CGFloat {
        switch expression.mood {
        case .confused:     return -0.5
        case .error:        return -0.7
        case .thinking:     return 0.2
        case .happy:        return 0.15
        case .naughty:      return 0.4
        default:            return 0.0
        }
    }

    private var rightBrowTilt: CGFloat {
        switch expression.mood {
        case .confused:     return 0.5
        case .error:        return 0.3
        case .thinking:     return -0.2
        case .happy:        return -0.15
        case .naughty:      return -0.6
        default:            return 0.0
        }
    }

    private var gazeOffset: CGSize {
        guard let gaze else { return .zero }
        let dx = (gaze.x - 0.5) * size * 0.04
        let dy = (gaze.y - 0.5) * size * 0.03
        return CGSize(width: dx, height: dy)
    }

    // MARK: - Animation loops

    private func startIdleLoop() {
        guard !reduceMotion else {
            breath = 1.0
            blinkPhase = 1.0
            return
        }
        withAnimation(BobMotion.breath) {
            breath = 1.022
        }
        // Blink loop — fast close, slower open, randomized via phase ratio.
        Task { @MainActor in
            while !reduceMotion {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 3_500_000_000...6_000_000_000))
                guard !reduceMotion else { break }
                withAnimation(.easeIn(duration: 0.10)) { blinkPhase = 0.05 }
                try? await Task.sleep(nanoseconds: 110_000_000)
                withAnimation(.easeOut(duration: 0.14)) { blinkPhase = 1.0 }
            }
        }
    }
}

// MARK: - Custom shapes

private struct HairCrescent: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // Top ~40% of the head, with an asymmetric side part.
        path.addArc(center: center, radius: r,
                    startAngle: .degrees(195), endAngle: .degrees(345),
                    clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - r * 0.15, y: rect.minY + r * 0.55))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r * 0.30, y: rect.minY + r * 0.40),
                          control: CGPoint(x: rect.midX + r * 0.10, y: rect.minY + r * 0.05))
        path.closeSubpath()
        return path
    }
}

private struct MouthShape: Shape {
    /// -1 (frown) ... 0 (flat) ... 1 (smile)
    var curvature: CGFloat
    /// 0 (closed line) ... 1 (open oval)
    var openness: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(curvature, openness) }
        set {
            curvature = newValue.first
            openness = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if openness < 0.15 {
            // Just a curved line.
            let yMid = rect.midY
            let lift = curvature * rect.height * 0.55
            path.move(to: CGPoint(x: rect.minX, y: yMid))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: yMid),
                control: CGPoint(x: rect.midX, y: yMid + lift)
            )
        } else {
            // Open mouth ellipse, taller for more "speaking" intensity.
            let h = rect.height * (0.30 + 0.70 * openness)
            let oval = CGRect(
                x: rect.minX + rect.width * 0.1,
                y: rect.midY - h / 2 + curvature * rect.height * 0.20,
                width: rect.width * 0.8,
                height: h
            )
            path.addEllipse(in: oval)
        }
        return path
    }
}

private struct BrowShape: Shape {
    /// -1 (worried, inner-low) ... 0 (level) ... 1 (raised)
    var tilt: CGFloat

    var animatableData: CGFloat {
        get { tilt }
        set { tilt = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let lift = tilt * rect.height * 0.6
        path.move(to: CGPoint(x: rect.minX, y: rect.midY - lift))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY + lift * 0.4),
            control: CGPoint(x: rect.midX, y: rect.midY - rect.height * 0.5)
        )
        return path
    }
}

private struct PoloCollar: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // V-neck collar shape — two angled flaps meeting at a notch.
        let notchY = rect.midY
        let notchX = rect.midX
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.15))
        path.addQuadCurve(
            to: CGPoint(x: notchX, y: notchY),
            control: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.10)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.15),
            control: CGPoint(x: rect.maxX - rect.width * 0.30, y: rect.minY + rect.height * 0.10)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
