import Foundation

enum GitDiffTool {
    static func execute(repoPath: String, relativePath: String?, staged: Bool) async -> ToolResult {
        var arguments = ["diff"]
        if staged {
            arguments.append("--cached")
        }

        let trimmedRelativePath = relativePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedRelativePath.isEmpty == false {
            arguments.append(contentsOf: ["--", trimmedRelativePath])
        }

        return await GitToolRunner.run(
            toolName: "git_diff",
            repoPath: repoPath,
            arguments: arguments
        )
    }
}
