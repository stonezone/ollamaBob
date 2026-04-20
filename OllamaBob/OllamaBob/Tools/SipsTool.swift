import Foundation

/// Image conversion and optional resize via native `sips`.
enum SipsTool {
    private static let allowedFormats: Set<String> = ["jpeg", "png", "tiff", "heic", "gif", "bmp"]

    static func execute(inputPath: String, outputPath: String, format: String, maxDimension: Int?) async -> ToolResult {
        let start = Date()
        let normalizedFormat = format.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard allowedFormats.contains(normalizedFormat) else {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(
                tool: "image_convert",
                error: "Unsupported format '\(format)'. Allowed: jpeg, png, tiff, heic, gif, bmp.",
                durationMs: durationMs
            )
        }

        if let value = maxDimension, (value < 16 || value > 16384) {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "image_convert", error: "max_dimension must be between 16 and 16384.", durationMs: durationMs)
        }

        var arguments = ["-s", "format", normalizedFormat]
        if let value = maxDimension {
            arguments += ["-Z", String(value)]
        }
        arguments += [inputPath, "--out", outputPath]

        let result = await ProcessRunner.run(
            executable: "/usr/bin/sips",
            arguments: arguments,
            timeout: 30
        )
        let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        if result.timedOut {
            return .failure(tool: "image_convert", error: "Command timed out after 30s", durationMs: durationMs)
        }

        if result.exitCode != 0 || trimmedStderr.contains("Error:") {
            let message = trimmedStderr.isEmpty ? "sips failed." : trimmedStderr
            return .failure(tool: "image_convert", error: message, durationMs: durationMs)
        }

        if result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(tool: "image_convert", error: "sips produced no output.", durationMs: durationMs)
        }

        let suffix = maxDimension.map { ", max \($0)px" } ?? ""
        return .success(tool: "image_convert", content: "Wrote \(outputPath) (\(normalizedFormat)\(suffix))", durationMs: durationMs)
    }
}
