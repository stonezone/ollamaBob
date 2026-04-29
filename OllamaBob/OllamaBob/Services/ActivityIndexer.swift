import Foundation

@MainActor
final class ActivityIndexer {
    static let shared = ActivityIndexer()

    private let isEnabled: @MainActor () -> Bool
    private let appendActivityEvent: (ActivityEvent) throws -> Int64

    init(
        isEnabled: @escaping @MainActor () -> Bool = { AppSettings.shared.activityTimelineEnabled },
        appendActivityEvent: @escaping (ActivityEvent) throws -> Int64 = { try DatabaseManager.shared.appendActivityEvent($0) }
    ) {
        self.isEnabled = isEnabled
        self.appendActivityEvent = appendActivityEvent
    }

    func recordToolCall(name: String, success: Bool, conversationID: String?) {
        guard isEnabled() else { return }
        let detail = "\(name) \(success ? "succeeded" : "failed")"
        let metadata = "{\"success\":\(success ? "true" : "false")}"
        append(ActivityEvent(
            id: nil,
            timestamp: Date(),
            source: "tool",
            kind: "tool_call",
            detail: capped(detail),
            conversationID: conversationID,
            metadataJSON: metadata
        ))
    }

    func recordChatMessage(role: String, conversationID: String?, summary: String?) {
        guard isEnabled() else { return }
        let normalizedRole = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let kind = normalizedRole.isEmpty ? "message" : "\(normalizedRole)_message"
        let fallback = normalizedRole.isEmpty ? "message" : "\(normalizedRole) message"
        let rawDetail = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = rawDetail?.isEmpty == false ? rawDetail! : fallback
        append(ActivityEvent(
            id: nil,
            timestamp: Date(),
            source: "chat",
            kind: kind,
            detail: capped(detail),
            conversationID: conversationID,
            metadataJSON: nil
        ))
    }

    func recordFileEvent(path: String, kind: String) {
    }

    private func append(_ event: ActivityEvent) {
        _ = try? appendActivityEvent(event)
    }

    private func capped(_ value: String) -> String {
        String(value.prefix(500))
    }
}
