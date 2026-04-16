import Foundation

enum FileMoveTool {
    static func execute(source: String, destination: String) async -> ToolResult {
        let start = Date()
        guard let sourceURL = FileToolPaths.resolvedURL(for: source) else {
            return .failure(tool: "move_file", error: "Missing source path.", durationMs: 0)
        }
        guard let destinationURL = FileToolPaths.resolvedURL(for: destination) else {
            return .failure(tool: "move_file", error: "Missing destination path.", durationMs: 0)
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .failure(tool: "move_file", error: "Source not found: \(source)", durationMs: 0)
        }

        let destinationParent = destinationURL.deletingLastPathComponent()
        var parentIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destinationParent.path, isDirectory: &parentIsDirectory) else {
            return .failure(tool: "move_file", error: "Destination parent does not exist: \(destinationParent.path)", durationMs: 0)
        }
        guard parentIsDirectory.boolValue else {
            return .failure(tool: "move_file", error: "Destination parent is not a directory: \(destinationParent.path)", durationMs: 0)
        }

        do {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .success(tool: "move_file", content: "Moved \(sourceURL.path) -> \(destinationURL.path)", durationMs: durationMs)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "move_file", error: error.localizedDescription, durationMs: durationMs)
        }
    }
}
