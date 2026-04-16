import Foundation

enum FileSearchTool {
    static func execute(pattern: String, path: String? = nil) async -> ToolResult {
        let start = Date()
        let searchPath = path.map { NSString(string: $0).expandingTildeInPath } ?? NSHomeDirectory()
        let results = searchFiles(pattern: pattern, in: searchPath, maxResults: AppConfig.fileSearchResultsMax)
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        if results.isEmpty {
            return .success(tool: "search_files", content: "No files found matching '\(pattern)' in \(searchPath)", durationMs: durationMs)
        }

        return .success(tool: "search_files", content: results.joined(separator: "\n"), durationMs: durationMs)
    }

    private static func searchFiles(pattern: String, in searchPath: String, maxResults: Int) -> [String] {
        guard !pattern.isEmpty else { return [] }

        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: searchPath).standardizedFileURL.resolvingSymlinksInPath()
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }

        let matcher = NameMatcher(pattern: pattern)
        let rootDepth = rootURL.pathComponents.count
        var matches: [String] = []

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        for case let url as URL in enumerator {
            let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
            let depth = canonicalURL.pathComponents.count - rootDepth

            if depth > 5 {
                continue
            }

            if matcher.matches(fileName: canonicalURL.lastPathComponent) {
                matches.append(canonicalURL.path)
                if matches.count >= maxResults {
                    break
                }
            }

            if depth >= 5, let values = try? canonicalURL.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true {
                enumerator.skipDescendants()
            }
        }

        return matches
    }
}

private struct NameMatcher {
    let pattern: String

    func matches(fileName: String) -> Bool {
        if pattern.contains("*") || pattern.contains("?") {
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".")
            let regex = "^\(escaped)$"
            return fileName.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
        }

        return fileName.range(of: pattern, options: [.caseInsensitive]) != nil
    }
}
