import Foundation

// MARK: - phone_inject
// Modal-gated. Injects text into an active call mid-conversation.
// Every invocation requires explicit user approval — posture is .modal.
// Added to isSideEffectingTool in AgentLoopToolDispatch.swift.

enum PhoneInjectTool {
    @MainActor
    static func execute(callID: String, text: String) async -> ToolResult {
        let start = Date()
        let client = JarvisCallClientFactory.current()
        do {
            let result = try await client.inject(callID: callID, text: text)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            let detail = result.detail.map { " detail=\($0)" } ?? ""
            if result.acknowledged {
                return .success(
                    tool: "phone_inject",
                    content: "Injected into callID=\(callID): acknowledged=true\(detail)",
                    durationMs: durationMs
                )
            } else {
                return .failure(
                    tool: "phone_inject",
                    error: "Inject not acknowledged for callID=\(callID)\(detail)",
                    durationMs: durationMs
                )
            }
        } catch let error as JarvisCallClientError {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "phone_inject", error: error.localizedDescription, durationMs: durationMs)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "phone_inject", error: error.localizedDescription, durationMs: durationMs)
        }
    }
}
