import Foundation

/// Code Companion Mode — enable_dev_mode tool (Phase 6).
///
/// Walks up from the given path to find the `.git` root, then stores that
/// root in `DevModeStore.shared`. While dev mode is active, `write_file`
/// calls whose target path is under the stored root are auto-approved
/// (ApprovalPolicy downgrades them from `.modal` to `.none`).
///
/// - Approval: `.modal` — the user explicitly authorizes the policy relaxation.
/// - Side-effecting: YES (changes session approval policy). Listed in
///   `AgentLoop.isSideEffectingTool`.
@MainActor
enum EnableDevModeTool {
    static func execute(path: String) -> ToolResult {
        guard let startURL = FileToolPaths.resolvedURL(for: path) else {
            return .failure(
                tool: "enable_dev_mode",
                error: "Invalid path: \(path)",
                durationMs: 0
            )
        }

        guard let repoRoot = ProjectContextTool.findGitRoot(from: startURL) else {
            return .failure(
                tool: "enable_dev_mode",
                error: "No .git repository found above \(startURL.path).",
                durationMs: 0
            )
        }

        let standardized = repoRoot.standardizedFileURL.path
        DevModeStore.shared.repoRoot = standardized

        return .success(
            tool: "enable_dev_mode",
            content: "Dev mode enabled for repo at \(standardized). "
                   + "write_file inside this repo will auto-approve. "
                   + "shell remains gated.",
            durationMs: 0
        )
    }
}
