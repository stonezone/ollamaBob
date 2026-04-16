import XCTest
@testable import OllamaBob

@MainActor
final class ChatSessionControllerTests: XCTestCase {
    func testLoadExistingConversationUsesInjectedDatabase() {
        let conversation = ConversationRecord(
            id: "convo-1",
            title: "Existing",
            isPinned: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        let storedMessages = [
            ChatMessage(role: .user, content: "hello"),
            ChatMessage(role: .assistant, content: "hi")
        ]
        let database = FakeDatabase(currentConversation: conversation, loadedMessages: storedMessages)
        let controller = ChatSessionController(
            agentLoop: FakeAgentLoop(),
            database: database,
            toolOutputStore: FakeToolOutputStore()
        )

        controller.loadExistingConversationIfNeeded()

        XCTAssertEqual(controller.conversationId, "convo-1")
        XCTAssertEqual(controller.messages.map { $0.content }, ["hello", "hi"])
        XCTAssertEqual(controller.history.map { $0.role }, ["user", "assistant"])
    }

    func testStartFreshConversationClearsPreviousSpilloutAndResetsState() async {
        let existing = ConversationRecord(
            id: "convo-old",
            title: "Existing",
            isPinned: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        let database = FakeDatabase(
            currentConversation: existing,
            loadedMessages: [ChatMessage(role: .user, content: "old")],
            createdConversation: ConversationRecord(
                id: "convo-new",
                title: "New Chat",
                isPinned: false,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        let toolOutputStore = FakeToolOutputStore()
        let controller = ChatSessionController(
            agentLoop: FakeAgentLoop(),
            database: database,
            toolOutputStore: toolOutputStore
        )
        controller.loadExistingConversationIfNeeded()
        controller.inputText = "draft"

        controller.startFreshConversation()
        await Task.yield()

        XCTAssertEqual(toolOutputStore.clearedConversationIDs, ["convo-old"])
        XCTAssertEqual(controller.conversationId, "convo-new")
        XCTAssertTrue(controller.messages.isEmpty)
        XCTAssertTrue(controller.history.isEmpty)
        XCTAssertEqual(controller.inputText, "")
        XCTAssertNil(controller.errorMessage)
    }

    func testSendCurrentInputUsesInjectedServices() async {
        let processExpectation = expectation(description: "agent loop called")
        let database = FakeDatabase(
            createdConversation: ConversationRecord(
                id: "convo-new",
                title: "New Chat",
                isPinned: false,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        let agentLoop = FakeAgentLoop()
        agentLoop.onProcess = { message, history, conversationId in
            processExpectation.fulfill()
            agentLoop.toolActivity = [
                AgentLoop.ToolLogEntry(
                    toolName: "shell",
                    input: "{\"command\":\"pwd\"}",
                    output: "/Users/zack/ollamaBob",
                    approval: .none,
                    approved: true,
                    durationMs: 12,
                    timestamp: Date()
                )
            ]
            return [
                .system("system"),
                .user(message),
                .assistant("Working on it"),
                .toolResult(name: "shell", content: "/Users/zack/ollamaBob")
            ]
        }

        let controller = ChatSessionController(
            agentLoop: agentLoop,
            database: database,
            toolOutputStore: FakeToolOutputStore()
        )
        controller.inputText = "pwd"

        controller.sendCurrentInput(allowsLocalCommands: false)
        await fulfillment(of: [processExpectation], timeout: 1.0)
        await Task.yield()

        XCTAssertEqual(controller.conversationId, "convo-new")
        XCTAssertEqual(controller.messages.map { $0.role }, [MessageRole.user, .assistant, .tool])
        XCTAssertEqual(controller.messages.map { $0.content }, ["pwd", "Working on it", "/Users/zack/ollamaBob"])
        XCTAssertEqual(database.savedMessages.count, 3)
        XCTAssertEqual(database.savedToolLogs.count, 1)
    }

    func testLoadExistingConversationIfNeededOnlyLoadsOnce() {
        let initialConversation = ConversationRecord(
            id: "convo-1",
            title: "Existing",
            isPinned: false,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let followUpConversation = ConversationRecord(
            id: "convo-2",
            title: "Changed",
            isPinned: false,
            createdAt: Date(timeIntervalSince1970: 3_000),
            updatedAt: Date(timeIntervalSince1970: 4_000)
        )
        let database = FakeDatabase(
            currentConversation: initialConversation,
            loadedMessages: [ChatMessage(role: .user, content: "hello")]
        )
        let controller = ChatSessionController(
            agentLoop: FakeAgentLoop(),
            database: database,
            toolOutputStore: FakeToolOutputStore()
        )

        controller.loadExistingConversationIfNeeded()
        database.currentConversationStub = followUpConversation
        database.loadedMessagesStub = [ChatMessage(role: .user, content: "different")]
        controller.loadExistingConversationIfNeeded()

        XCTAssertEqual(controller.conversationId, "convo-1")
        XCTAssertEqual(controller.messages.map { $0.content }, ["hello"])
        XCTAssertEqual(database.currentConversationCallCount, 1)
        XCTAssertEqual(database.loadMessagesCallCount, 1)
    }

    func testLoadConversationSnapshotReplacesStateAndUpdatesTitle() {
        let controller = ChatSessionController(
            agentLoop: FakeAgentLoop(),
            database: FakeDatabase(),
            toolOutputStore: FakeToolOutputStore()
        )
        let snapshot = ConversationSnapshot(
            id: "convo-42",
            title: "Renamed Thread",
            isPinned: false,
            messages: [
                ChatMessage(role: .user, content: "first"),
                ChatMessage(role: .assistant, content: "second")
            ],
            createdAt: Date(),
            updatedAt: Date()
        )

        controller.inputText = "draft"
        controller.loadConversation(snapshot)

        XCTAssertEqual(controller.conversationId, "convo-42")
        XCTAssertEqual(controller.conversationTitle, "Renamed Thread")
        XCTAssertEqual(controller.messages.map(\.content), ["first", "second"])
        XCTAssertEqual(controller.history.map(\.role), ["user", "assistant"])
        XCTAssertEqual(controller.inputText, "")
        XCTAssertNil(controller.errorMessage)
    }
}

private final class FakeDatabase: ChatSessionDatabaseManaging {
    var currentConversationStub: ConversationRecord?
    var loadedMessagesStub: [ChatMessage]
    var createdConversationStub: ConversationRecord
    var savedMessages: [ChatMessage] = []
    var savedToolLogs: [(conversationId: String, toolName: String)] = []
    var currentConversationCallCount = 0
    var loadMessagesCallCount = 0

    init(
        currentConversation: ConversationRecord? = nil,
        loadedMessages: [ChatMessage] = [],
        createdConversation: ConversationRecord = ConversationRecord(
            id: UUID().uuidString,
            title: "New Chat",
            isPinned: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    ) {
        self.currentConversationStub = currentConversation
        self.loadedMessagesStub = loadedMessages
        self.createdConversationStub = createdConversation
    }

    func currentConversation() throws -> ConversationRecord? {
        currentConversationCallCount += 1
        return currentConversationStub
    }

    func loadMessages(conversationId: String) throws -> [ChatMessage] {
        loadMessagesCallCount += 1
        return loadedMessagesStub
    }

    func createConversation(title: String) throws -> ConversationRecord {
        createdConversationStub
    }

    func saveMessage(_ msg: ChatMessage, conversationId: String) throws {
        savedMessages.append(msg)
    }

    func saveToolLog(
        conversationId: String,
        toolName: String,
        inputJson: String,
        outputText: String,
        approvalLevel: ApprovalLevel,
        approved: Bool,
        durationMs: Int
    ) throws {
        savedToolLogs.append((conversationId, toolName))
    }
}

@MainActor
private final class FakeAgentLoop: ChatSessionAgentLooping {
    var toolActivity: [AgentLoop.ToolLogEntry] = []
    var onProcess: ((String, [OllamaMessage], String) async throws -> [OllamaMessage])?

    func process(userMessage: String, history: [OllamaMessage], conversationId: String) async throws -> [OllamaMessage] {
        if let onProcess {
            return try await onProcess(userMessage, history, conversationId)
        }
        return history
    }
}

private final class FakeToolOutputStore: ChatSessionToolOutputStoring {
    var clearedConversationIDs: [String] = []

    func clearConversation(_ conversationId: String) async {
        clearedConversationIDs.append(conversationId)
    }
}
