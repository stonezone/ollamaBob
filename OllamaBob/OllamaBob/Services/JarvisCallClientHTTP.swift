import Foundation

// MARK: - JarvisCallClientHTTP
// Phase 4a stub: all methods throw .notImplemented.
// Phase 4b will replace these bodies with real HTTP calls to the Jarvis daemon.
// This is the production default — NOT gated by #if DEBUG.

final class JarvisCallClientHTTP: JarvisCallClient {

    func listCalls() async throws -> [JarvisCallSummary] {
        throw JarvisCallClientError.notImplemented
    }

    func transcript(callID: String) async throws -> JarvisTranscript {
        throw JarvisCallClientError.notImplemented
    }

    func inject(callID: String, text: String) async throws -> JarvisInjectResult {
        throw JarvisCallClientError.notImplemented
    }
}
