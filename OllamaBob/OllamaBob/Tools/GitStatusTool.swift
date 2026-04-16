import Foundation

enum GitStatusTool {
    static func execute(repoPath: String) async -> ToolResult {
        await GitToolRunner.run(
            toolName: "git_status",
            repoPath: repoPath,
            arguments: ["status", "--short", "--branch"]
        )
    }
}
