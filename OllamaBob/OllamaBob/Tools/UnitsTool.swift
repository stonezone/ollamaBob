import Foundation

/// Unit conversion wrapper around `/usr/bin/units`.
enum UnitsTool {
    static func execute(from fromValue: String, to toUnit: String) async -> ToolResult {
        let start = Date()
        let fromTrimmed = fromValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let toTrimmed = toUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fromTrimmed.isEmpty else {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "unit_convert", error: "Missing 'from' value.", durationMs: durationMs)
        }
        guard !toTrimmed.isEmpty else {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "unit_convert", error: "Missing 'to' unit.", durationMs: durationMs)
        }

        let result = await ProcessRunner.run(
            executable: "/usr/bin/units",
            arguments: ["-t", fromTrimmed, toTrimmed],
            timeout: 5
        )
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        if result.timedOut {
            return .failure(tool: "unit_convert", error: "Command timed out after 5s", durationMs: durationMs)
        }

        let trimmedStdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedStdout.isEmpty || trimmedStdout.lowercased().contains("conformability error") {
            let message = trimmedStderr.isEmpty ? "Cannot convert \(fromTrimmed) to \(toTrimmed)." : trimmedStderr
            return .failure(tool: "unit_convert", error: message, durationMs: durationMs)
        }

        return .success(
            tool: "unit_convert",
            content: "\(fromTrimmed) = \(trimmedStdout) \(toTrimmed)",
            durationMs: durationMs
        )
    }
}
