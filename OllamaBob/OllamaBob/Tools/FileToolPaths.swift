import Foundation

/// Shared path normalization for structured file tools.
enum FileToolPaths {
    static func resolvedURL(for rawPath: String) -> URL? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = NSString(string: trimmed).expandingTildeInPath
        let baseURL: URL
        if expanded.hasPrefix("/") {
            baseURL = URL(fileURLWithPath: expanded)
        } else {
            baseURL = URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: NSHomeDirectory()))
        }

        return baseURL.standardizedFileURL.resolvingSymlinksInPath()
    }
}
