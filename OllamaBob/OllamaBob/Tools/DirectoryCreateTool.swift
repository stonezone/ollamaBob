import Foundation

enum DirectoryCreateTool {
    static func execute(path: String, approvedResolvedPath: String? = nil) async -> ToolResult {
        let start = Date()
        guard let directoryURL = FileToolPaths.resolvedURL(for: path) else {
            return .failure(tool: "create_directory", error: "Missing directory path.", durationMs: 0)
        }

        if let approvedResolvedPath, directoryURL.path != approvedResolvedPath {
            return .failure(
                tool: "create_directory",
                error: "Approved resolved path changed before execution: \(approvedResolvedPath) -> \(directoryURL.path)",
                durationMs: 0
            )
        }

        switch PathPolicy.check(directoryURL.path) {
        case .denied:
            return .failure(tool: "create_directory", error: "Path is in a forbidden zone: \(directoryURL.path)", durationMs: 0)
        case .requiresApproval:
            guard approvedResolvedPath != nil else {
                return .failure(tool: "create_directory", error: "Path requires approval: \(directoryURL.path)", durationMs: 0)
            }
        case .allowed:
            break
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
