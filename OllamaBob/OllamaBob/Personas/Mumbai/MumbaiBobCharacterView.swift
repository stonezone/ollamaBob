import SwiftUI
import AppKit

/// Mumbai Bob — Pixar-style cartoon portrait of a friendly Indian
/// call-center employee-of-the-month. Animated sprite-sheet style: nine
/// pre-rendered PNG frames (center, four gaze directions, two blink
/// phases, smile-open, yawn) chosen at runtime based on cursor position
/// and a periodic blink/yawn schedule.
///
/// All frames share the same character likeness because they were
/// generated with the same reference image; the state machine just picks
/// which PNG to display each frame.
struct MumbaiBobCharacterView: View {

    let expression: BobPersonaExpression
    let palette: BobPersonaPalette
    let gaze: CGPoint?
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breath: CGFloat = 1.0
    @State private var animationOverride: AnimationOverride?
    @State private var blinkTask: Task<Void, Never>?
    @State private var yawnTask: Task<Void, Never>?

    private enum AnimationOverride: Equatable {
        case blinkHalf
        case blinkClosed
        case yawn
        case smileOpen

        var assetName: String {
            switch self {
            case .blinkHalf:    return "mumbai_bob_blink_half_alpha"
            case .blinkClosed:  return "mumbai_bob_blink_closed_alpha"
            case .yawn:         return "mumbai_bob_yawn_alpha"
            case .smileOpen:    return "mumbai_bob_smile_open_alpha"
            }
        }
    }

    var body: some View {
        ZStack {
            currentFrame
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .scaleEffect(breath)
        .onAppear { startIdleLoop() }
        .onChange(of: expression.mood) { _, _ in startIdleLoop() }
        .accessibilityElement()
        .accessibilityLabel("Mumbai Bob")
        .accessibilityValue(expression.mood.rawValue)
    }

    // MARK: - Frame selection

    private var currentFrame: Image {
        // Override > mood > gaze direction > center.
        if let override = animationOverride {
            return loadImage(override.assetName)
        }
        if let moodAsset = moodFrameOverride {
            return loadImage(moodAsset)
        }
        return loadImage(gazeAsset)
    }

    /// Mood-based frames take precedence over gaze tracking. Bob looks
    /// happy when he's actually speaking, eyes-up when thinking, etc.
    private var moodFrameOverride: String? {
        switch expression.mood {
        case .happy:        return "mumbai_bob_smile_open_alpha"
        case .speaking:     return "mumbai_bob_smile_open_alpha"
        case .thinking:     return "mumbai_bob_eyes_up_alpha"
        case .typing:       return "mumbai_bob_eyes_down_alpha"
        case .confused:     return "mumbai_bob_eyes_up_alpha"
        case .sheepish:     return "mumbai_bob_blink_half_alpha"
        case .listening:    return nil    // follow gaze
        case .error:        return "mumbai_bob_blink_half_alpha"
        case .idle:         return nil    // follow gaze
        case .naughty:      return "mumbai_bob_smile_open_alpha"
        }
    }

    /// Quantize the gaze CGPoint (each axis 0...1) into one of five frames:
    /// center / left / right / up / down. The thresholds are deliberately
    /// generous so the gaze locks to "center" most of the time and only
    /// shifts to a directional frame when the cursor is genuinely off to
    /// the side.
    private var gazeAsset: String {
        guard let gaze else { return "mumbai_bob_center_alpha" }
        let dx = gaze.x - 0.5
        let dy = gaze.y - 0.5
        let absDx = abs(dx)
        let absDy = abs(dy)
        let threshold: CGFloat = 0.18

        if absDx < threshold && absDy < threshold {
            return "mumbai_bob_center_alpha"
        }
        if absDx >= absDy {
            return dx > 0 ? "mumbai_bob_eyes_right_alpha" : "mumbai_bob_eyes_left_alpha"
        } else {
            return dy > 0 ? "mumbai_bob_eyes_down_alpha" : "mumbai_bob_eyes_up_alpha"
        }
    }

    /// Loads a sprite frame via `Bundle.module`. The frame PNGs live at
    /// the top level of the SPM resource bundle.
    private func loadImage(_ name: String) -> Image {
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "person.crop.circle")
    }

    // MARK: - Animation loops

    private func startIdleLoop() {
        // Cancel any previously-running tasks first. SwiftUI may call
        // `.onAppear` and `.onChange(of: expression.mood)` repeatedly as
        // the chat window updates — without explicit cancellation we'd
        // accumulate concurrent blink/yawn tasks, each fighting to set
        // and clear `animationOverride`, which manifests as Bob freezing
        // mid-blink for several seconds at a time.
        blinkTask?.cancel()
        yawnTask?.cancel()
        animationOverride = nil

        guard !reduceMotion else {
            breath = 1.0
            return
        }
        withAnimation(BobMotion.breath) {
            breath = 1.022
        }
        blinkTask = Task { @MainActor in
            while !Task.isCancelled {
                let interval = Double.random(in: 4.0...6.5) * 1_000_000_000
                try? await Task.sleep(nanoseconds: UInt64(interval))
                if Task.isCancelled || reduceMotion { break }
                // Three-phase blink: open -> half -> closed -> half -> open.
                animationOverride = .blinkHalf
                try? await Task.sleep(nanoseconds: 60_000_000)
                if Task.isCancelled { break }
                animationOverride = .blinkClosed
                try? await Task.sleep(nanoseconds: 110_000_000)
                if Task.isCancelled { break }
                animationOverride = .blinkHalf
                try? await Task.sleep(nanoseconds: 60_000_000)
                if Task.isCancelled { break }
                animationOverride = nil
            }
        }
        yawnTask = Task { @MainActor in
            while !Task.isCancelled {
                // Yawn rarely — every 60-180s when Bob is idle.
                let interval = Double.random(in: 60.0...180.0) * 1_000_000_000
                try? await Task.sleep(nanoseconds: UInt64(interval))
                if Task.isCancelled || reduceMotion { break }
                guard expression.mood == .idle, animationOverride == nil else { continue }
                animationOverride = .yawn
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                animationOverride = nil
            }
        }
    }
}
