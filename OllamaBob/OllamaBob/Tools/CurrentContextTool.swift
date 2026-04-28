import Foundation

/// Composite context tool: returns active_window + selected Finder items +
/// clipboard metadata in a single result. Does NOT include screen OCR
/// (the user must explicitly call `screen_ocr` for that).
/// Read-only, no approval required.
/// Output is wrapped in `<untrusted>` tags because window titles, file paths,
/// and clipboard previews are all user-controlled data.
@MainActor
enum CurrentContextTool {

    static func execute() async -> ToolResult {
        let start   = Date()
        let context = await MacContextService.currentContext()
        let summary = context.currentContextSummary()
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        return .success(
            tool: "current_context",
            content: UntrustedWrapper.wrap(summary),
            durationMs: durationMs
        )
    }
}
