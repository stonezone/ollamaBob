import Combine
import Foundation

struct ConversationSummary: Identifiable, Sendable {
    let id: String
    var title: String
    var isPinned: Bool
    var uncensoredMode: Bool
    let createdAt: Date
    var updatedAt: Date
}

struct ConversationSnapshot: Identifiable, Sendable {
    let id: String
    var title: String
    var isPinned: Bool
    var uncensoredMode: Bool
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date
}

enum ConversationStoreError: LocalizedError {
    case invalidTitle

    var errorDescription: String? {
        switch self {
        case .invalidTitle:
            return "Conversation title cannot be empty."
        }
    }
}

protocol ConversationStoring: AnyObject {
    func listConversations() throws -> [ConversationSummary]
    func loadConversation(id: String) throws -> ConversationSnapshot?
    func renameConversation(id: String, title: String) throws -> ConversationSummary?
    func setConversationPinned(id: String, isPinned: Bool) throws -> ConversationSummary?
    func setConversationUncensoredMode(id: String, isEnabled: Bool) throws -> ConversationSummary?
    func deleteConversation(id: String) throws -> Bool
}

@MainActor
final class ConversationStoreController: ObservableObject {
    @Published private(set) var conversations: [ConversationSummary] = []
    @Published private(set) var selectedConversationId: String?
    @Published private(set) var loadedConversation: ConversationSnapshot?
    @Published private(set) var errorMessage: String?
    @Published var searchQuery = "" {
        didSet { applyFilter() }
    }

    private let store: ConversationStoring
    private var allConversations: [ConversationSummary] = []

    init(store: ConversationStoring = DatabaseManager.shared) {
        self.store = store
    }

    func clearError() {
        errorMessage = nil
    }

    func refreshConversations() {
        do {
            allConversations = try store.listConversations()
            applyFilter()
            if let selectedConversationId,
               conversations.contains(where: { $0.id == selectedConversationId }) == false {
                self.selectedConversationId = nil
                loadedConversation = nil
            }
        } catch {
            errorMessage = "Failed to load conversations: \(error.localizedDescription)"
        }
    }

    func loadConversation(id: String) {
        do {
            selectedConversationId = id
            loadedConversation = try store.loadConversation(id: id)
            if loadedConversation == nil {
                errorMessage = "Conversation not found."
            }
        } catch {
            errorMessage = "Failed to load conversation: \(error.localizedDescription)"
        }
    }

    func selectConversation(id: String?) {
        guard let id else {
            selectedConversationId = nil
            loadedConversation = nil
            return
        }
        loadConversation(id: id)
    }

    func renameConversation(id: String, title: String) {
        do {
            guard let updated = try store.renameConversation(id: id, title: title) else {
                errorMessage = "Conversation not found."
                return
            }

            allConversations = allConversations.map {
                $0.id == updated.id ? updated : $0
            }
            applyFilter()

            if selectedConversationId == updated.id {
                loadedConversation?.title = updated.title
                loadedConversation?.updatedAt = updated.updatedAt
            }
        } catch {
            errorMessage = "Failed to rename conversation: \(error.localizedDescription)"
        }
    }

    func deleteConversation(id: String) {
        do {
            guard try store.deleteConversation(id: id) else {
                errorMessage = "Conversation not found."
                return
            }

            allConversations.removeAll { $0.id == id }
            applyFilter()
            if selectedConversationId == id {
                selectedConversationId = nil
                loadedConversation = nil
            }
        } catch {
            errorMessage = "Failed to delete conversation: \(error.localizedDescription)"
        }
    }

    func togglePinned(id: String) {
        guard let conversation = allConversations.first(where: { $0.id == id }) else { return }

        do {
            guard let updated = try store.setConversationPinned(id: id, isPinned: !conversation.isPinned) else {
                errorMessage = "Conversation not found."
                return
            }

            allConversations = allConversations.map {
                $0.id == updated.id ? updated : $0
            }
            allConversations.sort(by: Self.sortConversations)
            applyFilter()

            if selectedConversationId == updated.id {
                loadedConversation?.isPinned = updated.isPinned
                loadedConversation?.updatedAt = updated.updatedAt
            }
        } catch {
            errorMessage = "Failed to update pin: \(error.localizedDescription)"
        }
    }

    private func applyFilter() {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            conversations = allConversations.sorted(by: Self.sortConversations)
            return
        }

        conversations = allConversations
            .filter { $0.title.localizedCaseInsensitiveContains(trimmedQuery) }
            .sorted(by: Self.sortConversations)
    }

    private static func sortConversations(_ lhs: ConversationSummary, _ rhs: ConversationSummary) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.createdAt > rhs.createdAt
    }
}

extension DatabaseManager: ConversationStoring {}
