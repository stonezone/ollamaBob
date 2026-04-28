import Foundation

// MARK: - phone_list_calls
// Read-only. Lists active calls from the Jarvis call client (mock or HTTP).
// No approval required — read-only, no side effects.

enum PhoneListCallsTool {
    @MainActor
    static func execute() async -> ToolResult {
        let start = Date()
        let client = JarvisCallClientFactory.current()
        do {
            let calls = try await client.listCalls()
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            if calls.isEmpty {
                return .success(tool: "phone_list_calls", content: "No active calls.", durationMs: durationMs)
            }
            let lines = calls.map { call -> String in
                "callID=\(call.callID) to=\(call.to) persona=\(call.persona) status=\(call.status) duration=\(call.durationSeconds)s"
            }
            return .success(
                tool: "phone_list_calls",
                content: "Active calls (\(calls.count)):\n\(lines.joined(separator: "\n"))",
                durationMs: durationMs
            )
        } catch let error as JarvisCallClientError {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "phone_list_calls", error: error.localizedDescription, durationMs: durationMs)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "phone_list_calls", error: error.localizedDescription, durationMs: durationMs)
        }
    }
}

extension JarvisCallClientError {
    var localizedDescription: String {
        switch self {
        case .notImplemented:
            return "Jarvis call supervision is not yet implemented (Phase 4b)."
        case .daemonUnreachable:
            return "Jarvis daemon is unreachable."
        case .authFailure(let detail):
            return "Auth failure: \(detail)"
        case .other(let msg):
            return msg
        }
    }
}
