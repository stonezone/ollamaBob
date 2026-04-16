import Foundation

enum FileWriteTool {
    static func execute(path: String, content: String) async -> ToolResult {
        let start = Date()
        guard let fileURL = FileToolPaths.resolvedURL(for: path) else {
            return .failure(tool: "write_file", error: "Missing file path.", durationMs: 0)
        }

        let parentURL = fileURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parentURL.path, isDirectory: &isDirectory) else {
            return .failure(tool: "write_file", error: "Parent directory does not exist: \(parentURL.path)", durationMs: 0)
        }
        guard isDirectory.boolValue else {
            return .failure(tool: "write_file", error: "Parent is not a directory: \(parentURL.path)", durationMs: 0)
        }

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .success(tool: "write_file", content: "Wrote \(content.utf8.count) byte(s) to \(fileURL.path)", durationMs: durationMs)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "write_file", error: error.localizedDescription, durationMs: durationMs)
        }
    }
}
