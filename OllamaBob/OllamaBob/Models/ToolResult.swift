import Foundation

struct ToolResult: Sendable {
    let toolName: String
    let content: String
    let success: Bool
    let durationMs: Int

    static func success(tool: String, content: String, durationMs: Int) -> ToolResult {
        ToolResult(toolName: tool, content: content, success: true, durationMs: durationMs)
    }

    static func failure(tool: String, error: String, durationMs: Int) -> ToolResult {
        ToolResult(toolName: tool, content: "Error: \(error)", success: false, durationMs: durationMs)
    }

    static func denied(tool: String, reason: String) -> ToolResult {
        ToolResult(toolName: tool, content: "Denied: \(reason)", success: false, durationMs: 0)
    }

    static func forbidden(tool: String) -> ToolResult {
        ToolResult(toolName: tool, content: "Forbidden: This action is not allowed and will never be executed.", success: false, durationMs: 0)
    }
}
