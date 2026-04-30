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
}

enum JarvisCallClientError: Error, Equatable {
    case notImplemented
    case daemonUnreachable
    case authFailure(String)
    case other(String)
}
