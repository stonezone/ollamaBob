import Foundation

enum FileMoveTool {
    static func execute(
        source: String,
        destination: String,
        approvedSourcePath: String? = nil,
        approvedDestinationPath: String? = nil
    ) async -> ToolResult {
        let start = Date()
        guard let sourceURL = FileToolPaths.resolvedURL(for: source) else {
            return .failure(tool: "move_file", error: "Missing source path.", durationMs: 0)
        }
        guard let destinationURL = FileToolPaths.resolvedURL(for: destination) else {
            return .failure(tool: "move_file", error: "Missing destination path.", durationMs: 0)
        }

        if let approvedSourcePath, sourceURL.path != approvedSourcePath {
            return .failure(
                tool: "move_file",
                error: "Approved source path changed before execution: \(approvedSourcePath) -> \(sourceURL.path)",
                durationMs: 0
            )
        }
        if let approvedDestinationPath, destinationURL.path != approvedDestinationPath {
            return .failure(
                tool: "move_file",
                error: "Approved destination path changed before execution: \(approvedDestinationPath) -> \(destinationURL.path)",
                durationMs: 0
            )
        }

        switch PathPolicy.check(sourceURL.path) {
        case .denied:
            return .failure(tool: "move_file", error: "Source path is in a forbidden zone: \(sourceURL.path)", durationMs: 0)
        case .requiresApproval:
            guard approvedSourcePath != nil else {
                return .failure(tool: "move_file", error: "Source path requires approval: \(sourceURL.path)", durationMs: 0)
            }
        case .allowed:
            break
        }

        switch PathPolicy.check(destinationURL.path) {
        case .denied:
            return .failure(tool: "move_file", error: "Destination path is in a forbidden zone: \(destinationURL.path)", durationMs: 0)
        case .requiresApproval:
            guard approvedDestinationPath != nil else {
                return .failure(tool: "move_file", error: "Destination path requires approval: \(destinationURL.path)", durationMs: 0)
            }
        case .allowed:
            break
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
