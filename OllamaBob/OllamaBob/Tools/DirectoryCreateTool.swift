import Foundation

enum DirectoryCreateTool {
    static func execute(path: String) async -> ToolResult {
        let start = Date()
        guard let directoryURL = FileToolPaths.resolvedURL(for: path) else {
            return .failure(tool: "create_directory", error: "Missing directory path.", durationMs: 0)
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                return .success(tool: "create_directory", content: "Directory already exists: \(directoryURL.path)", durationMs: Int(Date().timeIntervalSince(start) * 1000))
            }
            return .failure(tool: "create_directory", error: "A file already exists at: \(directoryURL.path)", durationMs: 0)
        }

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .success(tool: "create_directory", content: "Created directory: \(directoryURL.path)", durationMs: durationMs)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "create_directory", error: error.localizedDescription, durationMs: durationMs)
        }
    }
}
