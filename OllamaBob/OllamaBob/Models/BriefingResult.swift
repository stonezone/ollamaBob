import Foundation

/// The outcome of one briefing run — both the Bob-synthesized summary and
/// the raw bounded tool outputs that produced it.
struct BriefingResult: Equatable, Sendable {

    // MARK: - Properties

    /// Stable database row id. 0 before the row is persisted.
    let id: Int64

    /// Wall-clock time the briefing was executed.
    let runAt: Date

    /// Bob's synthesized summary of the tool outputs.
    /// If Ollama was unreachable, this is a plain concatenation of `toolResults`.
    let summary: String

    /// Raw tool outputs, each wrapped with `<untrusted>…</untrusted>`.
    let toolResults: [String]

    /// `true` when the run completed without fatal errors; `false` if all
    /// safe-list tools failed or the runner encountered an unexpected error.
    let success: Bool

    // MARK: - Convenience

    /// Returns a copy stamped with a database row id after persistence.
    func withID(_ newID: Int64) -> BriefingResult {
        BriefingResult(
            id: newID,
            runAt: runAt,
            summary: summary,
            toolResults: toolResults,
            success: success
        )
    }
}
