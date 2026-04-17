import Foundation

/// YouTube search/download via yt-dlp.
enum YouTubeTool {
    private static let maxSearchChars = 5_000
    private static let installHint = "yt-dlp not found on PATH. Install with: brew install yt-dlp"
    private static let allowedFormats: Set<String> = ["mp3", "m4a", "mp4", "bestaudio", "bestvideo"]

    static func search(query: String, limit: Int?) async -> ToolResult {
        let start = Date()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "youtube_search", error: "Query is empty.", durationMs: durationMs)
        }

        guard let ytdlp = whichYtDlp() else {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "youtube_search", error: installHint, durationMs: durationMs)
        }

        let clamped = max(1, min(10, limit ?? 5))
        let term = "ytsearch\(clamped):\(trimmed)"
        let run = runProcess(executable: ytdlp, arguments: ["--dump-json", "--no-warnings", term], timeoutSeconds: 30)
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        if run.timedOut {
            return .failure(tool: "youtube_search", error: "Command timed out after 30s", durationMs: durationMs)
        }
        if run.exitCode != 0 {
            let err = run.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(tool: "youtube_search", error: err.isEmpty ? "yt-dlp search failed." : err, durationMs: durationMs)
        }

        let lines = run.stdout.split(whereSeparator: \.isNewline)
        var entries: [String] = []
        for (idx, line) in lines.enumerated() {
            guard let data = String(line).data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                continue
            }
            let title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(untitled)"
            let uploader = (obj["uploader"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(unknown uploader)"
            let url = (obj["webpage_url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(missing url)"
            let durationText = formatDuration(durationSeconds: obj["duration"])
            entries.append("\(idx + 1). [\(durationText)] \(title) — \(uploader)\n   \(url)")
        }

        let body = entries.isEmpty ? "(no results)" : entries.joined(separator: "\n")
        return .success(tool: "youtube_search", content: OutputLimits.truncate(body, max: maxSearchChars), durationMs: durationMs)
    }

    static func download(url: String, format: String, outputDir: String?) async -> ToolResult {
        let start = Date()
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFormat = format.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedURL.isEmpty else {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "youtube_download", error: "URL is empty.", durationMs: durationMs)
        }
        guard (trimmedURL.hasPrefix("http://") || trimmedURL.hasPrefix("https://")) && trimmedURL.lowercased().contains("youtu") else {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "youtube_download", error: "URL must be a full YouTube http(s) URL.", durationMs: durationMs)
        }
        guard allowedFormats.contains(normalizedFormat) else {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "youtube_download", error: "Unsupported format '\(format)'. Allowed: mp3, m4a, mp4, bestaudio, bestvideo.", durationMs: durationMs)
        }
        guard let ytdlp = whichYtDlp() else {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "youtube_download", error: installHint, durationMs: durationMs)
        }

        let isAudio = ["mp3", "m4a", "bestaudio"].contains(normalizedFormat)
        let rawOutputDir = outputDir?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? outputDir!
            : (isAudio ? "~/Music/Bob/" : "~/Downloads/Bob/")
        let resolvedDir = NSString(string: rawOutputDir).expandingTildeInPath
        do {
            try FileManager.default.createDirectory(atPath: resolvedDir, withIntermediateDirectories: true)
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "youtube_download", error: error.localizedDescription, durationMs: durationMs)
        }

        let outputTemplate = "\(resolvedDir)/%(title)s.%(ext)s"
        var args: [String]
        switch normalizedFormat {
        case "mp3":
            args = ["-x", "--audio-format", "mp3", "-o", outputTemplate, trimmedURL]
        case "m4a":
            args = ["-x", "--audio-format", "m4a", "-o", outputTemplate, trimmedURL]
        case "bestaudio":
            args = ["-f", "bestaudio", "-o", outputTemplate, trimmedURL]
        case "mp4":
            args = ["-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4", "-o", outputTemplate, trimmedURL]
        default:
            args = ["-f", "bestvideo", "-o", outputTemplate, trimmedURL]
        }

        let run = runProcess(executable: ytdlp, arguments: args, timeoutSeconds: 300)
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        if run.timedOut {
            return .failure(tool: "youtube_download", error: "Command timed out after 300s", durationMs: durationMs)
        }
        if run.exitCode != 0 {
            let err = run.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(tool: "youtube_download", error: err.isEmpty ? "yt-dlp download failed." : err, durationMs: durationMs)
        }

        var savedPath: String?
        for raw in run.stderr.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if let range = line.range(of: "[download] Destination: ") {
                savedPath = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let range = line.range(of: "[ExtractAudio] Destination: ") {
                savedPath = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let finalPath = savedPath?.isEmpty == false ? savedPath! : resolvedDir
        return .success(tool: "youtube_download", content: "Downloaded to \(finalPath)", durationMs: durationMs)
    }

    private static func whichYtDlp() -> String? {
        let result = runProcess(executable: "/usr/bin/which", arguments: ["yt-dlp"], timeoutSeconds: 5)
        guard !result.timedOut, result.exitCode == 0 else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private static func formatDuration(durationSeconds: Any?) -> String {
        let seconds: Int
        if let i = durationSeconds as? Int {
            seconds = i
        } else if let d = durationSeconds as? Double {
            seconds = Int(d)
        } else if let n = durationSeconds as? NSNumber {
            seconds = n.intValue
        } else {
            return "?:??"
        }
        let mins = max(0, seconds) / 60
        let secs = max(0, seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private struct ProcessRun {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let timedOut: Bool
    }

    private static func runProcess(executable: String, arguments: [String], timeoutSeconds: TimeInterval) -> ProcessRun {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var timedOut = false
        let timeoutItem = DispatchWorkItem {
            timedOut = true
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutItem)

        do {
            try process.run()
            process.waitUntilExit()
            timeoutItem.cancel()
        } catch {
            timeoutItem.cancel()
            return ProcessRun(exitCode: -1, stdout: "", stderr: error.localizedDescription, timedOut: false)
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProcessRun(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr, timedOut: timedOut)
    }
}
