import Foundation

// MARK: - AgentLoop / Approval Gate
//
// Phase 2a (peer-review plan, 2026-04-28): extracted from AgentLoop.swift.
// Owns the modal-approval await. The per-tool Auto/Ask/Deny badge resolution
// itself lives in `ApprovalPolicy.swift` (unchanged); this seam is the
// thin async hop between the agent loop and the user-facing modal handler.
//
// Method visibility is preserved as `private`; the only callers are
// instance methods on `AgentLoop`. This extension exists to make the
// approval-await responsibility findable in its own file rather than
// buried at the bottom of AgentLoop.swift.
extension AgentLoop {

    func requestApproval(command: String, toolName: String, level: ApprovalLevel) async -> Bool {
        guard let handler = approvalHandler else { return false }
        return await handler(command, toolName, level)
    }
}
