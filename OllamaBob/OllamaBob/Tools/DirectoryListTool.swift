import Foundation

enum DirectoryListTool {
    private static let maxEntries = 200

    static func execute(path: String, depth: Int = 1) async -> ToolResult {
        let start = Date()
        guard let rootURL = FileToolPaths.resolvedURL(for: path) else {
            return .failure(tool: "list_directory", error: "Missing directory path.", durationMs: 0)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else {
            return .failure(tool: "list_directory", error: "Directory not found: \(path)", durationMs: 0)
        }
        guard isDirectory.boolValue else {
            return .failure(tool: "list_directory", error: "Not a directory: \(path)", durationMs: 0)
        }

        let maxDepth = max(1, min(depth, 3))
        var entryCount = 0
        var visited = Set<String>()
        var entries = collectEntries(
            in: rootURL,
            currentDepth: 1,
            maxDepth: maxDepth,
            entryCount: &entryCount,
            visited: &visited
        )
        if entryCount >= maxEntries {
            entries.append("... [TRUNCATED: showing first \(maxEntries) entries] ...")
        }
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        guard !entries.isEmpty else {
            return .success(tool: "list_directory", content: "Directory is empty: \(rootURL.path)", durationMs: durationMs)
        }

        let header = "Directory listing for \(rootURL.path) (depth \(maxDepth)):"
        return .success(tool: "list_directory", content: ([header] + entries).joined(separator: "\n"), durationMs: durationMs)
    }

    private static func collectEntries(
        in directoryURL: URL,
        currentDepth: Int,
        maxDepth: Int,
        entryCount: inout Int,
        visited: inout Set<String>
    ) -> [String] {
        let fileManager = FileManager.default
        let canonicalDirectory = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
        if !visited.insert(canonicalDirectory.path).inserted {
            return []
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: canonicalDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        let sortedChildren = children.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        var lines: [String] = []

        for childURL in sortedChildren {
            if entryCount >= maxEntries {
                break
            }
            let canonicalURL = childURL.standardizedFileURL.resolvingSymlinksInPath()
            let resourceValues = try? canonicalURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues?.isDirectory ?? false
            lines.append("\(isDirectory ? "[DIR]" : "[FILE]") \(canonicalURL.path)")
            entryCount += 1

            if isDirectory, currentDepth < maxDepth {
                lines.append(contentsOf: collectEntries(
                    in: canonicalURL,
                    currentDepth: currentDepth + 1,
                    maxDepth: maxDepth,
                    entryCount: &entryCount,
                    visited: &visited
                ))
            }
        }

        return lines
    }
}
