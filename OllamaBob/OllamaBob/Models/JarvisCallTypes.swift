import Foundation

// MARK: - Jarvis Call Supervision Protocol and Value Types
// Call supervision protocol shared by the DEBUG mock and production HTTP client.

protocol JarvisCallClient: Sendable {
    func listCalls() async throws -> [JarvisCallSummary]
    func transcript(callID: String) async throws -> JarvisTranscript
    func inject(callID: String, text: String) async throws -> JarvisInjectResult
    /// Fetch the post-call extraction (outcome / followUps / facts / topics)
    /// for a finalized call. Returns `nil` when extraction was skipped (call
    /// too short, voicemail) or hasn't run yet — UI should treat both cases
    /// as "no action items to show".
    func actionItems(callID: String) async throws -> JarvisCallActionItems?
    /// v1.0.55: tri-state status from `/call/status/:id`
    /// (`actionItemsStatus` field). Lets the UI render "Extracting…" while
    /// the daemon's LLM pass is running instead of speculative-fetching
    /// and getting a 404. Returns `nil` for older daemons that don't emit
    /// the field — caller should treat nil as "fetch and see what
    /// happens", matching pre-v1.0.55 behavior.
    func actionItemsStatus(callID: String) async throws -> JarvisActionItemsStatus
}

/// State of action-items extraction for a finalized call. Mirrors the
/// daemon's `actionItemsStatus` tri-state shipped 2026-05-04.
enum JarvisActionItemsStatus: String, Equatable, Sendable {
    /// LLM extraction is running. UI should show "Extracting…" and
    /// re-poll in a few seconds rather than fetching the items.
    case pending
    /// Extraction completed; items are fetchable.
    case ready
    /// Daemon decided to skip extraction (call too short, voicemail,
    /// no transcript). UI should render "No action items" and not
    /// retry.
    case skipped
    /// Extraction errored. UI should render "Extraction failed" and
    /// not retry.
    case failed
    /// Daemon predates 2026-05-04 and doesn't emit the field, OR the
    /// call hasn't ended yet. Fall back to legacy behavior (fetch
    /// and treat 404 as "no items").
    case unknown
}

struct JarvisCallSummary: Equatable, Sendable {
    let callID: String
    let to: String
    let persona: String
    let status: String           // "ringing" | "in_progress" | "ended"
    let startedAt: Date
    let durationSeconds: Int
}

struct JarvisTranscript: Equatable, Sendable {
    let callID: String
    let lines: [Line]

    struct Line: Equatable, Sendable {
        let speaker: String      // "caller" | "callee"
        let text: String
        let at: Date
    }
}

struct JarvisInjectResult: Equatable, Sendable {
    let callID: String
    let acknowledged: Bool
    let detail: String?
}

/// Post-call action items extracted by the Jarvis daemon's LLM pass.
/// Mirrors `ExtractedCallFacts` on the daemon side. `followUps` are the
/// user-visible "Bob noticed: …" bullets surfaced after a call ends.
struct JarvisCallActionItems: Equatable, Sendable {
    let callID: String
    let outcome: String
    let followUps: [String]
    let facts: [String]
    let topics: [String]
    /// v1.0.55: optional URL to the cached recording MP3 served by the
    /// Jarvis daemon (added daemon-side in commit 31d9be7). UI renders
    /// a Play button when set so the user can replay the conversation.
    /// `nil` when recording is disabled, the call wasn't recorded, or
    /// the daemon predates the field.
    let recordingUrl: String?
}

enum JarvisCallClientError: Error, Equatable {
    case notImplemented
    case daemonUnreachable
    case authFailure(String)
    case other(String)
}
