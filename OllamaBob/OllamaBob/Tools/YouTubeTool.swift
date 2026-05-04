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
        // v1.0.49: switched from `--dump-json` to `--print` with a
        // pipe-delimited template. `--dump-json` returned the full
        // metadata document per result (every video format, every
        // storyboard, every thumbnail URL) — ~200 KB per result. With
        // 5 results that approached or exceeded ProcessRunner's 1 MB
        // stdout cap, which would cause us to send SIGTERM mid-stream
        // and yt-dlp would exit 15. The template format below is ~80
        // bytes per result so 5–10 results stay well under any limit.
        // Fields: id|title|channel|duration_seconds|webpage_url.
        // idle=30/hardCap=120 still applies as defense.
        let printTemplate = "%(id)s|%(title)s|%(channel)s|%(duration)s|%(webpage_url)s"
        let run = await ProcessRunner.run(
            executable: ytdlp,
            arguments: [
                "--no-warnings",
                "--flat-playlist",
                "--print", printTemplate,
                term
            ],
            idleTimeout: 30,
            hardCap: 120
        )
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        if run.timedOut {
            let why = run.idleTimedOut ? "idle for 30s" : (run.hardCapped ? "hard cap of 120s" : "timed out")
            return .failure(tool: "youtube_search", error: "yt-dlp search killed: \(why)", durationMs: durationMs)
        }
        // v1.0.49: explicit check for output-limit termination so we
        // report the real cause instead of a generic exit code.
        // (Previous behavior surfaced as "exited 15" — SIGTERM —
        // which is misleading since yt-dlp didn't fail; we killed it.)
        if run.outputLimitExceeded {
            return .failure(
                tool: "youtube_search",
                error: "yt-dlp search produced more than \(AppConfig.processOutputMaxBytes / 1024) KB of output and was terminated. Try a more specific query (artist + song name) for fewer results.",
                durationMs: durationMs
            )
        }
        if run.exitCode != 0 {
            // v1.0.47: surface the exit code AND a stdout/stderr preview so
            // the model (and the debug log) can see what actually went wrong.
            let stderrTrim = run.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdoutTail = String(run.stdout.suffix(400)).trimmingCharacters(in: .whitespacesAndNewlines)
            var diagnostic = "yt-dlp search exited \(run.exitCode)."
            if !stderrTrim.isEmpty {
                diagnostic += " stderr: \(stderrTrim.prefix(400))"
            }
            if stderrTrim.isEmpty && !stdoutTail.isEmpty {
                diagnostic += " stdout-tail: \(stdoutTail)"
            }
            if stderrTrim.isEmpty && stdoutTail.isEmpty {
                diagnostic += " (no output — likely network/DNS issue or transient yt-dlp glitch; retry the same query once)."
            }
            return .failure(tool: "youtube_search", error: diagnostic, durationMs: durationMs)
        }

        // Parse pipe-delimited output. Empty or all-whitespace lines
        // are skipped (yt-dlp sometimes emits a trailing newline).
        // Field positions: 0=id, 1=title, 2=channel, 3=duration_seconds, 4=webpage_url.
        var entries: [String] = []
        var idx = 0
        for raw in run.stdout.split(whereSeparator: \.isNewline) {
            let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let fields = line.components(separatedBy: "|")
            guard fields.count >= 5 else { continue }
            idx += 1
            let title = fields[1].isEmpty ? "(untitled)" : fields[1]
            let uploader = fields[2].isEmpty || fields[2] == "NA" ? "(unknown uploader)" : fields[2]
            let url = fields[4].isEmpty ? "(missing url)" : fields[4]
            let durationText = formatDuration(durationSeconds: Double(fields[3]))
            entries.append("\(idx). [\(durationText)] \(title) — \(uploader)\n   \(url)")
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

        // v1.0.46: migrated from legacy `timeout: 300` (fixed wall clock)
        // to idle/hardCap. yt-dlp prints download progress every ~1s
        // during the download phase, so idle=120 lets a slow connection
        // keep going as long as bytes are arriving. hardCap=1800 (30min)
        // is the absolute ceiling for a single track — anything over
        // that is almost certainly a stalled / re-encoding pathology.
        let run = await ProcessRunner.run(
            executable: ytdlp,
            arguments: args,
            idleTimeout: 120,
            hardCap: 1800
        )
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        if run.timedOut {
            let why = run.idleTimedOut
                ? "no progress from yt-dlp for 120s"
                : (run.hardCapped ? "exceeded 30-min hard cap" : "timed out")
            return .failure(tool: "youtube_download", error: "yt-dlp killed: \(why)", durationMs: durationMs)
        }
        // v1.0.49: report the real cause when ProcessRunner SIGTERM'd
        // due to output cap (rare for download but possible if yt-dlp
        // dumps verbose progress at high frequency).
        if run.outputLimitExceeded {
            return .failure(
                tool: "youtube_download",
                error: "yt-dlp produced more than \(AppConfig.processOutputMaxBytes / 1024) KB of progress output and was terminated. The download may have partially succeeded — check the destination folder.",
                durationMs: durationMs
            )
        }
        if run.exitCode != 0 {
            // v1.0.47: same informativeness fix as youtube_search above.
            let stderrTrim = run.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdoutTail = String(run.stdout.suffix(400)).trimmingCharacters(in: .whitespacesAndNewlines)
            var diagnostic = "yt-dlp download exited \(run.exitCode)."
            if !stderrTrim.isEmpty {
                diagnostic += " stderr: \(stderrTrim.prefix(400))"
            }
            if stderrTrim.isEmpty && !stdoutTail.isEmpty {
                diagnostic += " stdout-tail: \(stdoutTail)"
            }
            if stderrTrim.isEmpty && stdoutTail.isEmpty {
                diagnostic += " (no output — likely network/DNS issue or transient yt-dlp glitch)."
            }
            return .failure(tool: "youtube_download", error: diagnostic, durationMs: durationMs)
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
