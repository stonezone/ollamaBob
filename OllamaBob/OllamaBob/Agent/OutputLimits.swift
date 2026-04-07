import Foundation

enum OutputLimits {
    static func truncate(_ output: String, max: Int) -> String {
        guard output.count > max else { return output }
        let truncated = String(output.prefix(max))
        return "\(truncated)\n\n... [TRUNCATED: \(output.count) total chars, showing first \(max)] ..."
    }

    static func truncateShellStdout(_ output: String) -> String {
        truncate(output, max: AppConfig.shellStdoutMax)
    }

    static func truncateShellStderr(_ output: String) -> String {
        truncate(output, max: AppConfig.shellStderrMax)
    }

    static func truncateFileContent(_ content: String) -> String {
        truncate(content, max: AppConfig.fileReadMax)
    }

    static func truncateSnippet(_ snippet: String) -> String {
        truncate(snippet, max: AppConfig.searchSnippetMax)
    }
}
