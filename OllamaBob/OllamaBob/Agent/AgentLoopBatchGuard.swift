import Foundation

// MARK: - AgentLoop / Batch Audio Continuation & Audit
//
// Phase 2a (peer-review plan, 2026-04-28): extracted from AgentLoop.swift to
// keep the orchestration core focused. All entry points remain `static`
// methods on `AgentLoop` so callers (including tests) keep using
// `AgentLoop.batchAudioAudit(...)`, `AgentLoop.shouldForceBatchAudioContinuation(...)`,
// etc. unchanged.
//
// Scope of this file:
//   - Detects whether a user message is a batch-audio request and what
//     tracks were named.
//   - Decides whether to nudge Bob to continue the batch instead of
//     emitting a status-only "next up..." reply.
//   - After the batch, audits which tracks actually landed on disk and
//     which are missing.
extension AgentLoop {

    // MARK: - Continuation guard

    static func shouldForceBatchAudioContinuation(
        userMessage: String,
        assistantContent: String,
        lastToolResult: ToolResult?,
        loopBudget: LoopBudget,
        nudgeCount: Int
    ) -> Bool {
        guard loopBudget == LoopBudget(
            maxIterations: AppConfig.batchAudioAgentLoopMaxIterations,
            timeoutSeconds: AppConfig.batchAudioAgentLoopTimeoutSeconds
        ) else {
            return false
        }
        guard nudgeCount < AppConfig.batchAudioContinuationNudgeMax else {
            return false
        }
        guard lastToolResult?.success == true else {
            return false
        }

        let normalizedUser = userMessage
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let normalizedContent = assistantContent
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let batchMarkers = [
            "all these", "remaining", "next up", "track list",
            "songs", "tracks", "album", "playlist"
        ]
        guard batchMarkers.contains(where: { normalizedUser.contains($0) }) else {
            return false
        }

        let statusOnlyContinuationMarkers = [
            "next up", "next track", "is the track", "<channel|>"
        ]
        return statusOnlyContinuationMarkers.contains { normalizedContent.contains($0) }
    }

    // MARK: - Audit

    static func batchAudioAudit(userMessage: String, messages: [OllamaMessage]) -> BatchAudioAudit? {
        let requested = requestedBatchAudioTracks(userMessage: userMessage, messages: messages)
        guard requested.count >= 2 else { return nil }

        let downloadedPaths = messages
            .filter { $0.role == "tool" && $0.toolName == "youtube_download" }
            .compactMap { downloadedPath(from: $0.content) }

        let downloadedTracks = downloadedPaths.map { trackTitle(fromDownloadedPath: $0) }
        let downloadedKeys = Set(downloadedTracks.map(normalizedTrackKey))
        let missing = requested.filter { downloadedKeys.contains(normalizedTrackKey($0)) == false }
        let requestedKeys = Set(requested.map(normalizedTrackKey))
        let unmatched = downloadedTracks.filter { requestedKeys.contains(normalizedTrackKey($0)) == false }
        let outputDirectory = mostRecentCommonDirectory(from: downloadedPaths)

        return BatchAudioAudit(
            requestedTracks: requested,
            downloadedTracks: downloadedTracks,
            missingTracks: missing,
            unmatchedDownloads: unmatched,
            outputDirectory: outputDirectory
        )
    }

    static func requestedBatchAudioTracks(userMessage: String, messages: [OllamaMessage]) -> [String] {
        var candidates = [userMessage]
        candidates.append(contentsOf: messages
            .filter { $0.role == "user" }
            .map(\.content)
            .reversed())

        var seenMessages = Set<String>()
        for candidate in candidates {
            let key = candidate
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
            guard key.isEmpty == false, seenMessages.insert(key).inserted else { continue }
            let tracks = requestedBatchAudioTracks(from: candidate)
            if tracks.count >= 2 {
                return tracks
            }
        }
        return []
    }

    static func requestedBatchAudioTracks(from userMessage: String) -> [String] {
        let rawLines = userMessage
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var candidates: [String] = []
        for (index, rawLine) in rawLines.enumerated() {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if index == 0, let colon = line.lastIndex(of: ":") {
                line = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            line = line.replacingOccurrences(
                of: #"^\s*(?:[-*•]\s+|\d{1,3}[\.)-]\s*)"#,
                with: "",
                options: .regularExpression
            )
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isLikelyTrackLine(line) else { continue }
            candidates.append(line)
        }

        var seen = Set<String>()
        return candidates.filter { track in
            let key = normalizedTrackKey(track)
            guard !key.isEmpty, seen.contains(key) == false else { return false }
            seen.insert(key)
            return true
        }
    }

    static func shouldForceBatchAudioAuditContinuation(
        audit: BatchAudioAudit?,
        assistantContent: String,
        lastToolResult: ToolResult?,
        loopBudget: LoopBudget,
        nudgeCount: Int
    ) -> Bool {
        guard let audit, audit.missingTracks.isEmpty == false else { return false }
        guard loopBudget == LoopBudget(
            maxIterations: AppConfig.batchAudioAgentLoopMaxIterations,
            timeoutSeconds: AppConfig.batchAudioAgentLoopTimeoutSeconds
        ) else {
            return false
        }
        guard nudgeCount < AppConfig.batchAudioContinuationNudgeMax else { return false }
        guard lastToolResult?.success == true else { return false }

        let normalizedContent = assistantContent
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        if normalizedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        let completionClaims = [
            "complete", "completed", "done", "finished", "all tools finished",
            "successful", "successfully", "got them", "downloaded them"
        ]
        return completionClaims.contains { normalizedContent.contains($0) }
    }

    static func shouldReplaceBatchAudioFinalContent(_ content: String, audit: BatchAudioAudit) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        let normalizedContent = trimmed
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let hasCount = normalizedContent.contains("\(audit.downloadedTracks.count)")
            && normalizedContent.contains("\(audit.requestedTracks.count)")
        if audit.missingTracks.isEmpty {
            return hasCount == false
        }
        let mentionsMissing = normalizedContent.contains("missing")
            || normalizedContent.contains("skipped")
            || normalizedContent.contains("failed")
        return mentionsMissing == false
    }

    static func batchAudioAuditNudge(audit: BatchAudioAudit) -> String {
        let missingPreview = audit.missingTracks.prefix(12).joined(separator: ", ")
        let more = audit.missingTracks.count > 12 ? ", ..." : ""
        return """
        Batch audio audit: only \(audit.downloadedTracks.count) of \(audit.requestedTracks.count) requested tracks have a matching downloaded MP3. Missing: \(missingPreview)\(more).
        Do not claim completion. Immediately continue the batch by calling `youtube_search` for the first missing track: \(audit.missingTracks.first ?? "unknown"). Continue through the remaining missing tracks unless a track is truly ambiguous, denied, or fails.
        """
    }

    static func batchAudioFinalSummary(audit: BatchAudioAudit) -> String {
        var lines: [String] = []
        let location = audit.outputDirectory.map { " in \($0)" } ?? ""
        lines.append("Downloaded \(audit.downloadedTracks.count) of \(audit.requestedTracks.count) requested tracks\(location).")
        if audit.missingTracks.isEmpty {
            lines.append("No requested tracks are missing.")
        } else {
            lines.append("Missing: \(audit.missingTracks.joined(separator: ", ")).")
        }
        if audit.unmatchedDownloads.isEmpty == false {
            lines.append("Extra/unmatched downloads: \(audit.unmatchedDownloads.joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }

    static func batchAudioContinuationNudge(for assistantContent: String) -> String {
        let preview = assistantContent
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(300)
        return """
        Batch audio task is still in progress. Your last reply was status-only: "\(preview)".
        Do not answer with text only. If requested tracks remain, immediately call `youtube_search` for the next named track, or `youtube_download` if you already have a confirmed URL. Continue the batch until all listed tracks are complete, a track is truly ambiguous, a download is denied, or a tool fails.
        """
    }

    // MARK: - Private parsing helpers

    private static func isLikelyTrackLine(_ line: String) -> Bool {
        guard line.count >= 2, line.count <= 120 else { return false }
        let lowered = line.lowercased()
        let instructionPrefixes = [
            "search ", "download ", "grab ", "get ", "save ", "convert ",
            "please ", "bob ", "continue ", "skip ", "only "
        ]
        if instructionPrefixes.contains(where: { lowered.hasPrefix($0) }) {
            return false
        }
        let sentenceMarkers = [":", "http://", "https://"]
        if sentenceMarkers.contains(where: { lowered.contains($0) }) {
            return false
        }
        return true
    }

    private static func downloadedPath(from content: String) -> String? {
        guard let range = content.range(of: "Downloaded to ") else { return nil }
        let tail = content[range.upperBound...]
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return tail.isEmpty ? nil : tail
    }

    private static func trackTitle(fromDownloadedPath path: String) -> String {
        URL(fileURLWithPath: path)
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(
                of: #"^\s*\d{1,3}\s*[-_.]\s*"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedTrackKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func mostRecentCommonDirectory(from paths: [String]) -> String? {
        paths.last.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
    }
}
