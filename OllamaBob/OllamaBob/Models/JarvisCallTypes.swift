import Foundation

// MARK: - Jarvis Call Supervision Protocol and Value Types
// Phase 4a: protocol + mock implementation. Phase 4b: swap to real HTTP client.

protocol JarvisCallClient: Sendable {
    func listCalls() async throws -> [JarvisCallSummary]
    func transcript(callID: String) async throws -> JarvisTranscript
    func inject(callID: String, text: String) async throws -> JarvisInjectResult
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

enum JarvisCallClientError: Error, Equatable {
    case notImplemented
    case daemonUnreachable
    case authFailure(String)
    case other(String)
}
