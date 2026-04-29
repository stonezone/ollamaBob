import Foundation

/// Durable handoff for app-originated prompts that should be sent through
/// Bob's Desk even if the chat window is not mounted at the instant the event
/// fires.
@MainActor
final class DeskPromptInbox {
    static let shared = DeskPromptInbox()

    private var pending: [String] = []

    private init() {}

    func enqueue(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        pending.append(trimmed)
        NotificationCenter.default.post(name: .bobDeskPromptAvailable, object: nil)
    }

    func drain() -> [String] {
        let prompts = pending
        pending.removeAll()
        return prompts
    }

    #if DEBUG
    func resetForTesting() {
        pending.removeAll()
    }
    #endif
}

extension Notification.Name {
    static let bobDeskPromptAvailable = Notification.Name("com.ollamabob.deskPrompt.available")
}
