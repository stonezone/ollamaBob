import Foundation

enum FileWriteTool {
    static func execute(path: String, content: String) async -> ToolResult {
        let start = Date()
        guard let fileURL = FileToolPaths.resolvedURL(for: path) else {
            return .failure(tool: "write_file", error: "Missing file path.", durationMs: 0)
        }

        // Reject paths outside allowed zones
        switch PathPolicy.check(fileURL.path) {
        case .denied:
            return .failure(tool: "write_file", error: "Path is in a forbidden zone: \(fileURL.path)", durationMs: 0)
        case .requiresApproval:
            // ApprovalPolicy already gates this at .modal; reaching here means the user approved.
            break
        case .allowed:
            break
        }

        // Cap content at 100 KB
        let byteCount = content.utf8.count
        if byteCount > 100_000 {
            return .failure(tool: "write_file", error: "Content too large: \(byteCount) bytes (max 100,000)", durationMs: 0)
        }

        // Create parent directory if missing
        let parentURL = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "write_file", error: "Could not create parent directory: \(error.localizedDescription)", durationMs: durationMs)
        }

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .success(tool: "write_file", content: "Wrote \(byteCount) bytes to \(fileURL.path)", durationMs: durationMs)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "write_file", error: error.localizedDescription, durationMs: durationMs)
        }
    }
}
