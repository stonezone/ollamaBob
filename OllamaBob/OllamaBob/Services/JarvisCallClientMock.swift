import Foundation

#if DEBUG
// MARK: - JarvisCallClientMock
// DEBUG-ONLY deterministic mock for Phase 4a development and tests.
// This type MUST NOT be compiled into the release binary — the #if DEBUG
// gate is the enforcement mechanism. JarvisCallClientFactory never returns
// this type in a release build.

final class JarvisCallClientMock: JarvisCallClient, @unchecked Sendable {
    static let shared = JarvisCallClientMock()

    // Fixed call ID for the fixture active call
    static let fixtureCallID = "mock_call_001"

    private let lock = NSLock()
    private var _calls: [JarvisCallSummary]
    private var _transcripts: [String: JarvisTranscript]

    private init() {
        let start = Date().addingTimeInterval(-90)
        let fixtureCall = JarvisCallSummary(
            callID: Self.fixtureCallID,
            to: "Glennel",
            persona: "bob",
            status: "in_progress",
            startedAt: start,
            durationSeconds: 90
        )
        _calls = [fixtureCall]

        let transcript = JarvisTranscript(
            callID: Self.fixtureCallID,
            lines: [
                JarvisTranscript.Line(
                    speaker: "caller",
                    text: "Hey Glennel, how are you doing?",
                    at: start
                ),
                JarvisTranscript.Line(
                    speaker: "callee",
                    text: "I'm doing well, thanks for calling!",
                    at: start.addingTimeInterval(8)
                ),
            ]
        )
        _transcripts = [Self.fixtureCallID: transcript]
    }

    /// Reset to fixture state — useful in tests to avoid cross-test contamination.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        let start = Date().addingTimeInterval(-90)
        _calls = [
            JarvisCallSummary(
                callID: Self.fixtureCallID,
                to: "Glennel",
                persona: "bob",
                status: "in_progress",
                startedAt: start,
                durationSeconds: 90
            )
        ]
        _transcripts = [
            Self.fixtureCallID: JarvisTranscript(
                callID: Self.fixtureCallID,
                lines: [
                    JarvisTranscript.Line(
                        speaker: "caller",
                        text: "Hey Glennel, how are you doing?",
                        at: start
                    ),
                    JarvisTranscript.Line(
                        speaker: "callee",
                        text: "I'm doing well, thanks for calling!",
                        at: start.addingTimeInterval(8)
                    ),
                ]
            )
        ]
    }

    func listCalls() async throws -> [JarvisCallSummary] {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    func transcript(callID: String) async throws -> JarvisTranscript {
        lock.lock()
        defer { lock.unlock() }
        guard let t = _transcripts[callID] else {
            throw JarvisCallClientError.other("No transcript for callID=\(callID)")
        }
        return t
    }

    func actionItems(callID: String) async throws -> JarvisCallActionItems? {
        lock.lock()
        defer { lock.unlock() }
        guard _transcripts[callID] != nil else { return nil }
        return JarvisCallActionItems(
            callID: callID,
            outcome: "Mock call ended successfully.",
            followUps: [
                "Save Glennel's new number to contacts",
                "Follow up about the dinner Friday",
            ],
            facts: ["Glennel was at the office until 6pm."],
            topics: ["family", "logistics"]
        )
    }

    func inject(callID: String, text: String) async throws -> JarvisInjectResult {
        lock.lock()
        defer { lock.unlock() }
        guard _transcripts[callID] != nil else {
            throw JarvisCallClientError.other("No active call for callID=\(callID)")
        }
        let newLine = JarvisTranscript.Line(
            speaker: "caller",
            text: text,
            at: Date()
        )
        _transcripts[callID] = JarvisTranscript(
            callID: callID,
            lines: _transcripts[callID]!.lines + [newLine]
        )
        return JarvisInjectResult(callID: callID, acknowledged: true, detail: "Injected via mock")
    }
}
#endif
