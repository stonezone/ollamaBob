import Foundation
import Combine

/// Observable singleton that holds the most recently captured `MacContext`.
/// Lives on the main actor so SwiftUI views can observe it directly without
/// extra `receive(on:)` plumbing. `MacContextService` writes here after
/// every capture; the future `ContextChipView` reads from here.
@MainActor
final class MacContextStore: ObservableObject {
    static let shared = MacContextStore()

    /// The most recent context snapshot. `nil` until the first capture
    /// completes. Cleared when the user dismisses the ContextChipView.
    @Published private(set) var lastContext: MacContext?

    /// The raw OCR text from the most recent `screen_ocr` call. Kept
    /// separate because it can be large (up to ~10KB) and we don't want
    /// to embed it fully inside every `MacContext` snapshot.
    @Published private(set) var lastOCRText: String?

    private init() {}

    /// Called by `MacContextService` after each context capture.
    func update(_ context: MacContext) {
        lastContext = context
    }

    /// Called by `MacContextService` after a successful `screen_ocr` run.
    func updateOCR(_ text: String) {
        lastOCRText = text
        // Embed a 500-char snippet into lastContext if one exists.
        guard let existing = lastContext else { return }
        let snippet = String(text.prefix(500))
        lastContext = MacContext(
            capturedAt: existing.capturedAt,
            activeApp: existing.activeApp,
            selectedItems: existing.selectedItems,
            clipboardMeta: existing.clipboardMeta,
            screenOCRSnippet: snippet
        )
    }

    /// Clear context — called when the user dismisses the ContextChipView.
    func clear() {
        lastContext = nil
        lastOCRText = nil
    }
}
