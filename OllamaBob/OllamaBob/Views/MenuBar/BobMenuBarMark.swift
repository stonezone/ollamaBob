import SwiftUI

/// Custom-rendered menu bar icon. Replaces `Image(systemName: "bubble.left.fill")`.
///
/// SwiftUI's `MenuBarExtra` rasterizes its label into an `NSImage`, which
/// doesn't always render arbitrary vector views correctly at the menu bar's
/// 18pt template footprint. Using an SF Symbol as the base guarantees the
/// glyph is visible and template-tinted by macOS to match the menu bar's
/// light/dark appearance. A small status badge layers on top for processing
/// and error states; idle shows the bare symbol.
struct BobMenuBarMark: View {
    enum Status: Equatable {
        case idle
        case processing
        case error
    }

    let status: Status

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinPhase: Double = 0

    var body: some View {
        Image(systemName: "bubble.left.fill")
            .overlay(alignment: .topTrailing) { badge }
            .onAppear { startSpinIfNeeded() }
            .onChange(of: status) { startSpinIfNeeded() }
    }

    @ViewBuilder
    private var badge: some View {
        switch status {
        case .idle:
            EmptyView()

        case .processing:
            Circle()
                .trim(from: 0, to: 0.4)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(width: 7, height: 7)
                .rotationEffect(.degrees(spinPhase))
                .offset(x: 3, y: -3)

        case .error:
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .offset(x: 3, y: -3)
        }
    }

    private func startSpinIfNeeded() {
        guard status == .processing, !reduceMotion else {
            spinPhase = 0
            return
        }
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
            spinPhase = 360
        }
    }
}

extension BobMenuBarMark.Status {
    /// Maps an `AgentLoop` snapshot to a menu-bar mark state.
    static func resolve(isProcessing: Bool, hasError: Bool) -> BobMenuBarMark.Status {
        if hasError { return .error }
        if isProcessing { return .processing }
        return .idle
    }
}
