import Foundation

/// Lightweight bus shared between the chat scene and the floating HUD.
/// The chat publishes the latest assistant content snippet (and the active
/// persona's mood) here; the HUD subscribes via `@ObservedObject` to mirror
/// what Bob is saying without having to thread a session reference through
/// the HUD's owning scene.
///
/// Snippet length is capped at `Self.snippetCap` characters so the HUD
/// bubble stays compact regardless of the underlying message size.
@MainActor
final class HUDState: ObservableObject {
    static let shared = HUDState()

    /// Latest assistant text trimmed and truncated for HUD display. Empty
    /// when no assistant message is present (e.g. fresh conversation).
    @Published private(set) var latestAssistantSnippet: String = ""

    /// Number of characters retained from the original assistant content.
    /// Anything beyond is truncated with an ellipsis.
    static let snippetCap = 180

    private init() {}

    /// Publish a fresh assistant snippet. Trims surrounding whitespace and
    /// caps the length. Pass `nil` to clear (treated as empty string).
    func publishAssistantSnippet(_ raw: String?) {
        guard let raw else {
            if !latestAssistantSnippet.isEmpty { latestAssistantSnippet = "" }
            return
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = Self.truncate(trimmed, to: Self.snippetCap)
        if snippet != latestAssistantSnippet {
            latestAssistantSnippet = snippet
        }
    }

    /// Truncate a string to `cap` characters, appending `…` only when the
    /// original string actually exceeded the cap.
    static func truncate(_ raw: String, to cap: Int) -> String {
        guard raw.count > cap else { return raw }
        let endIndex = raw.index(raw.startIndex, offsetBy: cap)
        return String(raw[..<endIndex]) + "…"
    }
}
