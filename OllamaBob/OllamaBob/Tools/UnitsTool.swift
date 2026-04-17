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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/units")
        process.arguments = ["-t", fromTrimmed, toTrimmed]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var timedOut = false
        let timeoutItem = DispatchWorkItem {
            timedOut = true
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeoutItem)

        do {
            try process.run()
            process.waitUntilExit()
            timeoutItem.cancel()
        } catch {
            timeoutItem.cancel()
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "unit_convert", error: error.localizedDescription, durationMs: durationMs)
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        if timedOut {
            return .failure(tool: "unit_convert", error: "Command timed out after 5s", durationMs: durationMs)
        }

        let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
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
