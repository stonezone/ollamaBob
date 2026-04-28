import Foundation

/// A single row from the `execution_log` table, representing one approved
/// side-effecting tool execution. Read-only tools are never recorded.
struct ExecutionLogEntry: Identifiable, Equatable {
    let id: Int64
    let timestamp: Date
    let toolName: String
    let approvalLevel: ApprovalLevel
    let summary: String
    let success: Bool
    let durationMs: Int
}
