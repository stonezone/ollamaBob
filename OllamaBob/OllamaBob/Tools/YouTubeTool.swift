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

        guard let ytdlp = await whichYtDlp() else {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "youtube_search", error: installHint, durationMs: durationMs)
        }

        let clamped = max(1, min(10, limit ?? 5))
        let term = "ytsearch\(clamped):\(trimmed)"
        let run = await ProcessRunner.run(executable: ytdlp, arguments: ["--dump-json", "--no-warnings", term], timeout: 30)
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

    static func download(url: String, format: String, outputDir: String?, filename: String? = nil) async -> ToolResult {
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
        guard let ytdlp = await whichYtDlp() else {
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

        let outputTemplate = outputTemplate(resolvedDir: resolvedDir, filename: filename, format: normalizedFormat)
        let args = downloadArguments(url: trimmedURL, format: normalizedFormat, outputTemplate: outputTemplate)

        let run = await ProcessRunner.run(executable: ytdlp, arguments: args, timeout: 300)
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        if run.timedOut {
            return .failure(tool: "youtube_download", error: "Command timed out after 300s", durationMs: durationMs)
        }
        if run.exitCode != 0 {
            let err = run.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(tool: "youtube_download", error: err.isEmpty ? "yt-dlp download failed." : err, durationMs: durationMs)
        }

        var savedPath: String?
        let pathOutput = [run.stderr, run.stdout].joined(separator: "\n")
        let savedPathPrefix = resolvedDir.hasSuffix("/") ? resolvedDir : "\(resolvedDir)/"
        for raw in pathOutput.split(whereSeparator: \.isNewline) {
            let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if let range = line.range(of: "[download] Destination: ") {
                savedPath = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let range = line.range(of: "[ExtractAudio] Destination: ") {
                savedPath = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if line.hasPrefix(savedPathPrefix) {
                savedPath = line
            }
        }
        let finalPath = savedPath?.isEmpty == false ? savedPath! : resolvedDir
        return .success(tool: "youtube_download", content: "Downloaded to \(finalPath)", durationMs: durationMs)
    }

    static func downloadArguments(url: String, format: String, outputTemplate: String) -> [String] {
        let common = ["--no-playlist", "--print", "after_move:filepath", "-o", outputTemplate]
        switch format {
        case "mp3":
            return ["-x", "--audio-format", "mp3"] + common + [url]
        case "m4a":
            return ["-x", "--audio-format", "m4a"] + common + [url]
        case "bestaudio":
            return ["-f", "bestaudio"] + common + [url]
        case "mp4":
            return ["-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4"] + common + [url]
        default:
            return ["-f", "bestvideo"] + common + [url]
        }
    }

    static func outputTemplate(resolvedDir: String, filename: String?, format: String) -> String {
        let cleanDir = resolvedDir.hasSuffix("/") && resolvedDir.count > 1
            ? String(resolvedDir.dropLast())
            : resolvedDir
        let stem = sanitizedOutputStem(filename: filename, format: format) ?? "%(title)s"
        return "\(cleanDir)/\(stem).%(ext)s"
    }

    private static func sanitizedOutputStem(filename: String?, format: String) -> String? {
        guard var stem = filename?.trimmingCharacters(in: .whitespacesAndNewlines), !stem.isEmpty else {
            return nil
        }

        for separator in ["/", ":", "\\"] {
            stem = stem.replacingOccurrences(of: separator, with: "_")
        }
        stem = stem
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: "_")
            .replacingOccurrences(of: #"_+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "._- "))

        let mediaExtensions: Set<String> = ["mp3", "m4a", "mp4", "webm", "opus", "mkv"]
        let nsStem = stem as NSString
        let ext = nsStem.pathExtension.lowercased()
        if mediaExtensions.contains(ext) {
            stem = nsStem.deletingPathExtension
                .replacingOccurrences(of: #"_+"#, with: "_", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "._- "))
        }

        if stem.count > 180 {
            stem = String(stem.prefix(180)).trimmingCharacters(in: CharacterSet(charactersIn: "._- "))
        }

        return stem.isEmpty ? nil : stem
    }

    private static func whichYtDlp() async -> String? {
        // Use /bin/zsh -lc so PATH includes Homebrew even when the app
        // is launched from Finder (which doesn't source ~/.zshrc).
        let result = await ProcessRunner.run(executable: "/bin/zsh", arguments: ["-lc", "which yt-dlp"], timeout: 5)
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


}
