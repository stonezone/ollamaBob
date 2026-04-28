import Foundation

// MARK: - phone_get_transcript
// Read-only. Fetches the latest transcript chunk for a call_id.
// No approval required — read-only, no side effects.

enum PhoneTranscriptTool {
    @MainActor
    static func execute(callID: String) async -> ToolResult {
        let start = Date()
        let client = JarvisCallClientFactory.current()
        do {
            let transcript = try await client.transcript(callID: callID)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            if transcript.lines.isEmpty {
                return .success(
                    tool: "phone_get_transcript",
                    content: "Transcript for callID=\(callID): (no lines yet)",
                    durationMs: durationMs
                )
            }
            let formatter = ISO8601DateFormatter()
            let lines = transcript.lines.map { line -> String in
                "[\(line.speaker)] \(line.text)  (\(formatter.string(from: line.at)))"
            }
            return .success(
                tool: "phone_get_transcript",
                content: "Transcript for callID=\(callID) (\(transcript.lines.count) lines):\n\(lines.joined(separator: "\n"))",
                durationMs: durationMs
            )
        } catch let error as JarvisCallClientError {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "phone_get_transcript", error: error.localizedDescription, durationMs: durationMs)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "phone_get_transcript", error: error.localizedDescription, durationMs: durationMs)
        }
    }
}
