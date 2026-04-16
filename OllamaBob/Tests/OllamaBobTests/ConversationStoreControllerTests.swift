import XCTest
@testable import OllamaBob

@MainActor
final class ConversationStoreControllerTests: XCTestCase {
    func testRefreshSelectRenameAndDeleteConversation() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let updatedAt = Date(timeIntervalSince1970: 2_000)
        let conversation = ConversationSummary(
            id: "convo-1",
            title: "Original",
            isPinned: false,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let snapshot = ConversationSnapshot(
            id: "convo-1",
            title: "Original",
            isPinned: false,
            messages: [ChatMessage(role: .user, content: "hello")],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let store = FakeConversationStore(
            conversations: [conversation],
            snapshots: ["convo-1": snapshot]
        )
        let controller = ConversationStoreController(store: store)

        controller.refreshConversations()
        controller.selectConversation(id: "convo-1")

        XCTAssertEqual(controller.conversations.map(\.title), ["Original"])
        XCTAssertEqual(controller.selectedConversationId, "convo-1")
        XCTAssertEqual(controller.loadedConversation?.messages.map(\.content), ["hello"])

        controller.renameConversation(id: "convo-1", title: "Renamed")

        XCTAssertEqual(controller.conversations.first?.title, "Renamed")
        XCTAssertEqual(controller.loadedConversation?.title, "Renamed")

        controller.togglePinned(id: "convo-1")

        XCTAssertEqual(controller.conversations.first?.isPinned, true)
        XCTAssertEqual(controller.loadedConversation?.isPinned, true)

        controller.searchQuery = "rename"
        XCTAssertEqual(controller.conversations.count, 1)

        controller.searchQuery = "missing"
        XCTAssertTrue(controller.conversations.isEmpty)

        controller.deleteConversation(id: "convo-1")

        XCTAssertTrue(controller.conversations.isEmpty)
        XCTAssertNil(controller.selectedConversationId)
        XCTAssertNil(controller.loadedConversation)
        XCTAssertEqual(store.deletedIDs, ["convo-1"])
    }
}

private final class FakeConversationStore: ConversationStoring {
    var conversations: [ConversationSummary]
    var snapshots: [String: ConversationSnapshot]
    var deletedIDs: [String] = []

    init(
        conversations: [ConversationSummary] = [],
        snapshots: [String: ConversationSnapshot] = [:]
    ) {
        self.conversations = conversations
        self.snapshots = snapshots
    }

    func listConversations() throws -> [ConversationSummary] {
        conversations
    }

    func loadConversation(id: String) throws -> ConversationSnapshot? {
        snapshots[id]
    }

    func renameConversation(id: String, title: String) throws -> ConversationSummary? {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        conversations[index].title = title
        conversations[index].updatedAt = Date(timeIntervalSince1970: 3_000)
        if var snapshot = snapshots[id] {
            snapshot.title = title
            snapshot.updatedAt = conversations[index].updatedAt
            snapshots[id] = snapshot
        }
        return conversations[index]
    }

    func setConversationPinned(id: String, isPinned: Bool) throws -> ConversationSummary? {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        conversations[index].isPinned = isPinned
        conversations[index].updatedAt = Date(timeIntervalSince1970: 4_000)
        if var snapshot = snapshots[id] {
            snapshot.isPinned = isPinned
            snapshot.updatedAt = conversations[index].updatedAt
            snapshots[id] = snapshot
        }
        return conversations[index]
    }

    func deleteConversation(id: String) throws -> Bool {
        deletedIDs.append(id)
        conversations.removeAll { $0.id == id }
        snapshots[id] = nil
        return true
    }
}
