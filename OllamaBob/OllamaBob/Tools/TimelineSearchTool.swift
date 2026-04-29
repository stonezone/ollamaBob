import Foundation

@MainActor
enum TimelineSearchTool {
    typealias FetchActivityEvents = (Date, Date, String?, String?, Int) throws -> [ActivityEvent]

    static func execute(
        since rawSince: String,
        until rawUntil: String?,
        source: String?,
        kind: String?,
        limit: Int?,
        isEnabled: @MainActor () -> Bool = { AppSettings.shared.activityTimelineEnabled },
        fetchActivityEvents: FetchActivityEvents = { since, until, source, kind, limit in
            try DatabaseManager.shared.fetchActivityEvents(since: since, until: until, source: source, kind: kind, limit: limit)
        }
    ) -> ToolResult {
        let start = Date()
        guard isEnabled() else {
            return .denied(tool: "timeline_search", reason: "Activity Timeline (local) is disabled. Enable it in Preferences to search local activity.")
        }

        guard let since = parseISO8601(rawSince) else {
            return .failure(tool: "timeline_search", error: "Invalid ISO8601 date for since: \(rawSince)", durationMs: elapsed(since: start))
        }
        let until: Date
        if let rawUntil, !rawUntil.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let parsedUntil = parseISO8601(rawUntil) else {
                return .failure(tool: "timeline_search", error: "Invalid ISO8601 date for until: \(rawUntil)", durationMs: elapsed(since: start))
            }
            until = parsedUntil
        } else {
            until = Date()
        }

        do {
            let safeLimit = min(max(limit ?? 50, 1), 50)
            let events = try fetchActivityEvents(since, until, source, kind, safeLimit)
            let lines = events.prefix(50).map(formatEvent(_:))
            let output = lines.isEmpty ? "No activity events found." : lines.joined(separator: "\n")
            return .success(tool: "timeline_search", content: UntrustedWrapper.wrap(output, source: .tool("timeline_search")), durationMs: elapsed(since: start))
        } catch {
            return .failure(tool: "timeline_search", error: error.localizedDescription, durationMs: elapsed(since: start))
        }
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidates = hasExplicitTimeZone(trimmed) ? [trimmed] : [trimmed, trimmed + "Z"]
        for candidate in candidates {
            for options in isoOptions {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = options
                if let parsed = formatter.date(from: candidate) {
                    return parsed
                }
            }
        }
        return nil
    }

    private static let isoOptions: [ISO8601DateFormatter.Options] = [
        [.withInternetDateTime],
        [.withInternetDateTime, .withFractionalSeconds]
    ]

    private static func hasExplicitTimeZone(_ value: String) -> Bool {
        value.hasSuffix("Z")
            || value.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil
    }

    private static func formatEvent(_ event: ActivityEvent) -> String {
        let conversation = event.conversationID.map { String($0.prefix(8)) } ?? "-"
        let detail = event.detail.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return "[\(formatDate(event.timestamp))] \(event.source)/\(event.kind) \(conversation) \(detail)"
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func elapsed(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}
