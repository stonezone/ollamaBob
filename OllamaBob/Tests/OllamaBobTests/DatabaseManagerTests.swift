import XCTest
@testable import OllamaBob

final class DatabaseManagerTests: XCTestCase {
    override func tearDown() {
        DatabaseManager.shared.resetForTesting()
        super.tearDown()
    }

    func testSaveMessageUpdatesCurrentConversationOrdering() throws {
        try withTemporaryDatabase { manager in
            let older = try manager.createConversation(title: "Older")
            usleep(20_000)
            let newer = try manager.createConversation(title: "Newer")

            XCTAssertEqual(try manager.currentConversation()?.id, newer.id)

            usleep(20_000)
            try manager.saveMessage(ChatMessage(role: .user, content: "ping"), conversationId: older.id)

            XCTAssertEqual(try manager.currentConversation()?.id, older.id)
        }
    }

    func testLoadMessagesPreservesAssistantToolCalls() throws {
        try withTemporaryDatabase { manager in
            let conversation = try manager.createConversation()
            let toolCall = OllamaToolCall(
                id: "call-1",
                function: .init(
                    index: 0,
                    name: "read_file",
                    arguments: .object(["path": .string("/tmp/test.txt")])
                )
            )
            let assistant = ChatMessage(role: .assistant, content: "", toolCalls: [toolCall])

            try manager.saveMessage(assistant, conversationId: conversation.id)

            let loaded = try manager.loadMessages(conversationId: conversation.id)
            XCTAssertEqual(loaded.count, 1)
            XCTAssertEqual(loaded.first?.role, .assistant)
            XCTAssertEqual(loaded.first?.toolCalls?.count, 1)
            XCTAssertEqual(loaded.first?.toolCalls?.first?.function.name, "read_file")
            XCTAssertEqual(
                loaded.first?.toolCalls?.first?.function.parsedArguments["path"] as? String,
                "/tmp/test.txt"
            )
        }
    }

    func testListConversationsSortsPinnedFirstAndPersistsPinning() throws {
        try withTemporaryDatabase { manager in
            let first = try manager.createConversation(title: "First")
            usleep(10_000)
            let second = try manager.createConversation(title: "Second")

            _ = try manager.setConversationPinned(id: first.id, isPinned: true)

            let conversations = try manager.listConversations()
            XCTAssertEqual(conversations.map(\.id), [first.id, second.id])
            XCTAssertEqual(conversations.first?.isPinned, true)

            let loaded = try manager.loadConversation(id: first.id)
            XCTAssertEqual(loaded?.isPinned, true)
        }
    }

    private func withTemporaryDatabase(_ body: (DatabaseManager) throws -> Void) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dbURL = tempDir.appendingPathComponent("ollamabob.sqlite", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try DatabaseManager.shared.setup(at: dbURL)
        try body(DatabaseManager.shared)
    }
}
