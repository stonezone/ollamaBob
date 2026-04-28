import Foundation

/// Code Companion Mode — disable_dev_mode tool (Phase 6).
///
/// Clears `DevModeStore.shared.repoRoot`, restoring normal approval policy
/// for all tools. This is the safe direction — no side effects that could
/// damage anything — so approval is `.none`.
@MainActor
enum DisableDevModeTool {
    static func execute() -> ToolResult {
        DevModeStore.shared.repoRoot = nil
        return .success(
            tool: "disable_dev_mode",
            content: "Dev mode disabled. All file writes return to modal approval.",
            durationMs: 0
        )
    }
}
