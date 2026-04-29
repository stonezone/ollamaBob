import SwiftUI

/// Standalone status badge for walkie-talkie push-to-talk mode.
///
/// Shows "Listening…" while `SpeechService` is recording and "Speaking…"
/// while the synthesizer is active.  Shows nothing (`EmptyView`) when idle.
///
/// **Drop-in usage** — mounted by BobsDeskView and reusable elsewhere.
/// To show the indicator, overlay it from any parent view:
/// ```swift
/// .overlay(alignment: .topTrailing) { WalkieTalkieIndicator() }
/// ```
struct WalkieTalkieIndicator: View {

    @ObservedObject private var service = SpeechService.shared

    var body: some View {
        Group {
            switch service.state {
            case .recording:
                badge(label: "Listening…", color: .red, icon: "mic.fill")
            case .speaking:
                badge(label: "Speaking…", color: .blue, icon: "speaker.wave.2.fill")
            case .idle:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: service.state)
    }

    // MARK: Private

    @ViewBuilder
    private func badge(label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        WalkieTalkieIndicator()
    }
    .padding()
    .frame(width: 200, height: 100)
}
#endif
