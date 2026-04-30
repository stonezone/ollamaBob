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
        BobChip(label: label, tint: color, isProminent: true) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
        }
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
