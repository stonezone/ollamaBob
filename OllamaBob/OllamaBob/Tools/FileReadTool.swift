import Foundation

enum FileReadTool {
    static func execute(path: String) async -> ToolResult {
        let start = Date()
        let expandedPath = NSString(string: path).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return .failure(tool: "read_file", error: "File not found: \(path)", durationMs: 0)
        }

        guard FileManager.default.isReadableFile(atPath: expandedPath) else {
            return .failure(tool: "read_file", error: "Permission denied: \(path)", durationMs: 0)
        }

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: expandedPath)
            let size = attrs[.size] as? Int ?? 0
            if size > AppConfig.fileReadMax {
                // Read only up to the limit. The file existed when we checked above,
                // but it could have been removed/locked between then and now — guard,
                // don't crash.
                guard let handle = FileHandle(forReadingAtPath: expandedPath) else {
                    let durationMs = Int(Date().timeIntervalSince(start) * 1000)
                    return .failure(tool: "read_file", error: "Could not open file: \(path)", durationMs: durationMs)
                }
                let data = handle.readData(ofLength: AppConfig.fileReadMax)
                handle.closeFile()
                let content = String(data: data, encoding: .utf8) ?? "(binary content)"
                let durationMs = Int(Date().timeIntervalSince(start) * 1000)
                let truncated = content + "\n\n... [TRUNCATED: \(size) total bytes, showing first \(AppConfig.fileReadMax)] ..."
                return .success(tool: "read_file", content: truncated, durationMs: durationMs)
            }

            let content = try String(contentsOfFile: expandedPath, encoding: .utf8)
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .success(tool: "read_file", content: content, durationMs: durationMs)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "read_file", error: error.localizedDescription, durationMs: durationMs)
        }
    }
}
