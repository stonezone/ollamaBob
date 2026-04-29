import Foundation
import AppKit
import Combine

/// Passive clipboard observer that surfaces a `ClipboardSuggestion` in the
/// menu-bar dropdown when the clipboard content matches a known pattern.
///
/// Hard rules:
/// - Default OFF; must be enabled via `AppSettings.clipboardCortexEnabled`.
/// - Polling interval >= 1 second (never < 1s to avoid CPU drain).
/// - Non-text payloads (images, files) are silently skipped.
/// - Payloads > 32 KB are silently skipped.
/// - Classification is regex-only — no model invocation.
/// - Clipboard is NEVER mutated without an explicit user action (chip click).
@MainActor
final class ClipboardWatcher: ObservableObject {

    // MARK: - Singleton

    static let shared = ClipboardWatcher()

    // MARK: - Constants

    /// Maximum clipboard payload size we'll classify (32 KB).
    nonisolated static let maxPayloadBytes = 32 * 1024
    /// Minimum polling interval in seconds. Hard floor enforced in `start()`.
    nonisolated static let minPollingInterval: TimeInterval = 1.0
    /// Default polling interval.
    nonisolated static let defaultPollingInterval: TimeInterval = 1.5

    // MARK: - Published state

    /// The current suggestion, or `nil` when nothing useful was detected.
    /// Set to `nil` when the watcher is stopped.
    @Published private(set) var suggestion: ClipboardSuggestion?

    // MARK: - Private

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var pollingInterval: TimeInterval = defaultPollingInterval

    // MARK: - Lifecycle

    private init() {}

    /// Start polling at `interval` seconds. Enforces the 1-second minimum.
    func start(interval: TimeInterval = defaultPollingInterval) {
        let clamped = max(interval, Self.minPollingInterval)
        pollingInterval = clamped
        guard timer == nil else { return }
        // Seed the change count so we don't fire on stale clipboard content
        // that was already on the board when the watcher starts.
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: clamped, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    /// Stop polling and clear any pending suggestion.
    func stop() {
        timer?.invalidate()
        timer = nil
        suggestion = nil
    }

    // MARK: - Polling

    private func poll() {
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Skip non-text payloads
        guard pb.availableType(from: [.string]) != nil else { return }
        guard let text = pb.string(forType: .string) else { return }

        // Skip payloads larger than 32 KB
        guard text.utf8.count <= Self.maxPayloadBytes else { return }

        // Classify — pure regex, no model
        guard let kind = ClipboardClassifier.classify(text) else {
            suggestion = nil
            return
        }

        let preview = String(text.prefix(80))
        let newSuggestion = ClipboardSuggestion(kind: kind, preview: preview, detectedAt: Date())
        // Avoid re-publishing identical suggestions
        if suggestion != newSuggestion {
            suggestion = newSuggestion
        }
    }

    // MARK: - Cleanup actions (click-gated, no auto-mutation)

    /// Apply the cleanup for a given suggestion. Called ONLY when the user
    /// explicitly clicks the chip — never invoked automatically.
    ///
    /// Returns the cleaned string, or `nil` when no transform was applicable.
    /// The caller is responsible for writing the result back to the pasteboard
    /// if desired (so the write goes through an approval gate).
    func applyCleanup(for suggestion: ClipboardSuggestion) -> String? {
        let pb = NSPasteboard.general
        guard let raw = pb.string(forType: .string) else { return nil }

        switch suggestion.kind {
        case .messyURL:
            return ClipboardCleaners.cleanURL(raw)
        case .messyJSON:
            return ClipboardCleaners.prettyJSON(raw)
        case .base64Blob:
            return ClipboardCleaners.decodeBase64(raw)
        case .stackTrace, .generic:
            // Stack trace summarization requires an explicit Bob invocation
            // handled by the UI layer; we return nil here to signal "ask Bob".
            return nil
        }
    }
}
