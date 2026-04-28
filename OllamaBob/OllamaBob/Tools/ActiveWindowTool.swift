import Foundation

/// Returns the frontmost app bundle ID, name, and window title (when accessible).
/// Read-only, no approval required. Output is wrapped in `<untrusted>` tags
/// because the window title is user-controlled text that could contain injection
/// attempts.
@MainActor
enum ActiveWindowTool {

    static func execute() async -> ToolResult {
        let start = Date()
        let context = await MacContextService.activeWindow()
        let summary = context.activeWindowSummary()
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        return .success(
            tool: "active_window",
            content: UntrustedWrapper.wrap(summary),
            durationMs: durationMs
        )
    }
}
