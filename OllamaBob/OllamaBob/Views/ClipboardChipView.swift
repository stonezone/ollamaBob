import SwiftUI
import AppKit

/// Standalone chip that surfaces in the menu-bar dropdown when
/// `ClipboardWatcher` detects actionable clipboard content.
///
/// The chip performs the cleanup transform when tapped. For `.stackTrace` it
/// posts a notification so the chat window can send a Bob prompt instead.
struct ClipboardChipView: View {

    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var watcher = ClipboardWatcher.shared

    var body: some View {
        if let suggestion = watcher.suggestion {
            chipButton(for: suggestion)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
    }

    // MARK: - Private

    @ViewBuilder
    private func chipButton(for suggestion: ClipboardSuggestion) -> some View {
        Button {
            handleTap(for: suggestion)
        } label: {
            Label(suggestion.kind.chipLabel, systemImage: suggestion.kind.chipIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(chipAccent(suggestion.kind).opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(chipHelp(suggestion))
    }

    private func handleTap(for suggestion: ClipboardSuggestion) {
        if suggestion.kind == .stackTrace {
            let clipboardText = NSPasteboard.general.string(forType: .string) ?? suggestion.preview
            let notification = Notification(
                name: .clipboardCortexSummarizeStackTrace,
                object: nil,
                userInfo: [
                    "preview": suggestion.preview,
                    "content": clipboardText
                ]
            )
            if let prompt = DeskPromptActions.stackTracePrompt(from: notification) {
                DeskPromptInbox.shared.enqueue(prompt)
            }
            openWindow(id: "chat")
        } else if let cleaned = ClipboardWatcher.shared.applyCleanup(for: suggestion) {
            // Write cleaned result back to clipboard — user already opted in by
            // tapping the chip, so this is the user's explicit consent.
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(cleaned, forType: .string)
            // Clear the chip once the action is done.
            // The watcher will naturally suppress it on next poll because the
            // change count will have advanced and the new content won't match.
        }
    }

    private func chipAccent(_ kind: ClipboardSuggestion.Kind) -> Color {
        switch kind {
        case .messyURL:   return .blue
        case .messyJSON:  return .orange
        case .base64Blob: return .purple
        case .stackTrace: return .red
        case .generic:    return .green
        }
    }

    private func chipHelp(_ suggestion: ClipboardSuggestion) -> String {
        let truncated = suggestion.preview.count > 40
            ? String(suggestion.preview.prefix(40)) + "…"
            : suggestion.preview
        switch suggestion.kind {
        case .messyURL:   return "Strip tracking params from: \(truncated)"
        case .messyJSON:  return "Pretty-print JSON: \(truncated)"
        case .base64Blob: return "Decode base64: \(truncated)"
        case .stackTrace: return "Ask Bob to summarize stack trace"
        case .generic:    return "Clean clipboard content"
        }
    }
}

// MARK: - Notification name

extension Notification.Name {
    /// Posted when the user taps "Summarize stack trace" chip.
    /// `userInfo["content"]` contains the clipboard text and
    /// `userInfo["preview"]` contains the first 80 chars.
    static let clipboardCortexSummarizeStackTrace = Notification.Name(
        "com.ollamabob.clipboardCortex.summarizeStackTrace"
    )
}

#if DEBUG
#Preview("Chip visible") {
    VStack(spacing: 12) {
        ClipboardChipView()
    }
    .padding()
    .frame(width: 280, height: 80)
}
#endif
