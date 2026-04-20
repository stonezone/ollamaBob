import XCTest
@testable import OllamaBob

@MainActor
final class ChatSessionControllerTests: XCTestCase {
    func testLoadExistingConversationUsesInjectedDatabase() {
        let conversation = ConversationRecord(
            id: "convo-1",
            title: "Existing",
            isPinned: false,
            uncensoredMode: true,
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
        XCTAssertTrue(controller.conversationUncensoredMode)
        XCTAssertEqual(controller.messages.map { $0.content }, ["hello", "hi"])
        XCTAssertEqual(controller.history.map { $0.role }, ["user", "assistant"])
    }

    func testStartFreshConversationClearsPreviousSpilloutAndResetsState() async {
        let existing = ConversationRecord(
            id: "convo-old",
            title: "Existing",
            isPinned: false,
            uncensoredMode: true,
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
                uncensoredMode: false,
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
        for _ in 0..<10 where toolOutputStore.clearedConversationIDs.isEmpty {
            await Task.yield()
        }

        XCTAssertEqual(toolOutputStore.clearedConversationIDs, ["convo-old"])
        XCTAssertEqual(controller.conversationId, "convo-new")
        XCTAssertFalse(controller.conversationUncensoredMode)
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
                uncensoredMode: true,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        let agentLoop = FakeAgentLoop()
        agentLoop.onProcess = { message, history, conversationId, uncensoredMode in
            processExpectation.fulfill()
            XCTAssertTrue(uncensoredMode)
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
        controller.setConversationUncensoredMode(true)
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

    func testTranscriptRevisionAdvancesWhenCompletedTurnAppendsMessages() async {
        let processExpectation = expectation(description: "agent loop called")
        let database = FakeDatabase(
            createdConversation: ConversationRecord(
                id: "convo-revision",
                title: "New Chat",
                isPinned: false,
                uncensoredMode: false,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        let agentLoop = FakeAgentLoop()
        agentLoop.onProcess = { message, _, _, _ in
            processExpectation.fulfill()
            return [
                .user(message),
                .assistant("hello back")
            ]
        }

        let controller = ChatSessionController(
            agentLoop: agentLoop,
            database: database,
            toolOutputStore: FakeToolOutputStore()
        )
        controller.inputText = "hello"

        XCTAssertEqual(controller.transcriptRevision, 0)

        controller.sendCurrentInput(allowsLocalCommands: false)

        XCTAssertEqual(controller.transcriptRevision, 1)

        await fulfillment(of: [processExpectation], timeout: 1.0)
        await Task.yield()

        XCTAssertEqual(controller.transcriptRevision, 2)
        XCTAssertEqual(controller.messages.map(\.content), ["hello", "hello back"])
    }

    func testTranscriptRevisionStaysPutWhenCompletedTurnAddsNoMessages() async {
        let processExpectation = expectation(description: "agent loop called")
        let database = FakeDatabase(
            createdConversation: ConversationRecord(
                id: "convo-revision",
                title: "New Chat",
                isPinned: false,
                uncensoredMode: false,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        let agentLoop = FakeAgentLoop()
        agentLoop.onProcess = { message, _, _, _ in
            processExpectation.fulfill()
            return [
                .user(message)
            ]
        }

        let controller = ChatSessionController(
            agentLoop: agentLoop,
            database: database,
            toolOutputStore: FakeToolOutputStore()
        )
        controller.inputText = "hello"

        controller.sendCurrentInput(allowsLocalCommands: false)

        XCTAssertEqual(controller.transcriptRevision, 1)

        await fulfillment(of: [processExpectation], timeout: 1.0)
        await Task.yield()

        XCTAssertEqual(controller.transcriptRevision, 1)
        XCTAssertEqual(controller.messages.map(\.content), ["hello"])
    }

    func testToolBackedTurnPreservesThinkingAndAssistantContent() async {
        let processExpectation = expectation(description: "tool-backed turn processed")
        let database = FakeDatabase(
            createdConversation: ConversationRecord(
                id: "convo-disk",
                title: "New Chat",
                isPinned: false,
                uncensoredMode: false,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        let agentLoop = FakeAgentLoop()
        let toolCall = OllamaToolCall(
            id: "call-1",
            function: OllamaToolCall.FunctionCall(
                index: 0,
                name: "shell",
                arguments: .object(["command": .string("df -h")])
            )
        )
        agentLoop.onProcess = { message, history, conversationId, uncensoredMode in
            processExpectation.fulfill()
            XCTAssertFalse(uncensoredMode)
            return [
                .system("system"),
                .user(message),
                OllamaMessage(
                    role: "assistant",
                    content: "",
                    thinking: "Need the filesystem free space first.",
                    toolCalls: [toolCall]
                ),
                .toolResult(
                    name: "shell",
                    content: """
                    <untrusted>
                    Filesystem      Size   Used  Avail Capacity iused ifree %iused Mounted on
                    /dev/disk3s1s1 926Gi  12Gi 456Gi     3%  458k  4.3G    0%   /
                    </untrusted>
                    """
                ),
                .assistant(
                    """
                    Oh dear sir, Bob has the result right here for you sir.

                    Basically sir, from the main system volume it looks like you got wery good space, sir!

                    For the root filesystem ('/'), sir, you have about **456Gi** free. The usage is only at **3%**, sir.
                    """
                )
            ]
        }

        let controller = ChatSessionController(
            agentLoop: agentLoop,
            database: database,
            toolOutputStore: FakeToolOutputStore()
        )
        controller.inputText = "how much space is left on my drive?"

        controller.sendCurrentInput(allowsLocalCommands: false)
        await fulfillment(of: [processExpectation], timeout: 1.0)
        await Task.yield()

        XCTAssertEqual(controller.messages.map(\.role), [.user, .assistant, .tool, .assistant])
        XCTAssertEqual(controller.messages[1].thinking, "Need the filesystem free space first.")
        XCTAssertEqual(
            controller.messages[3].content,
            """
            Oh dear sir, Bob has the result right here for you sir.

            Basically sir, from the main system volume it looks like you got wery good space, sir!

            For the root filesystem ('/'), sir, you have about **456Gi** free. The usage is only at **3%**, sir.
            """
        )
    }

    func testLoadExistingConversationIfNeededOnlyLoadsOnce() {
        let initialConversation = ConversationRecord(
            id: "convo-1",
            title: "Existing",
            isPinned: false,
            uncensoredMode: false,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let followUpConversation = ConversationRecord(
            id: "convo-2",
            title: "Changed",
            isPinned: false,
            uncensoredMode: true,
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
            uncensoredMode: true,
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
        XCTAssertTrue(controller.conversationUncensoredMode)
        XCTAssertEqual(controller.messages.map(\.content), ["first", "second"])
        XCTAssertEqual(controller.history.map(\.role), ["user", "assistant"])
        XCTAssertEqual(controller.transcriptRevision, 1)
        XCTAssertEqual(controller.inputText, "")
        XCTAssertNil(controller.errorMessage)
    }

    func testToggleConversationUncensoredModePersistsForExistingConversation() {
        let conversation = ConversationRecord(
            id: "convo-1",
            title: "Existing",
            isPinned: false,
            uncensoredMode: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        let database = FakeDatabase(
            currentConversation: conversation,
            loadedMessages: [ChatMessage(role: .user, content: "hello")]
        )
        let controller = ChatSessionController(
            agentLoop: FakeAgentLoop(),
            database: database,
            toolOutputStore: FakeToolOutputStore()
        )

        controller.loadExistingConversationIfNeeded()
        controller.setConversationUncensoredMode(true)

        XCTAssertTrue(controller.conversationUncensoredMode)
        XCTAssertEqual(database.lastSetConversationUncensoredMode?.id, "convo-1")
        XCTAssertEqual(database.lastSetConversationUncensoredMode?.isEnabled, true)
    }
}

private final class FakeDatabase: ChatSessionDatabaseManaging {
    var currentConversationStub: ConversationRecord?
    var loadedMessagesStub: [ChatMessage]
    var createdConversationStub: ConversationRecord
    var savedMessages: [ChatMessage] = []
    var savedToolLogs: [(conversationId: String, toolName: String)] = []
    var lastSetConversationUncensoredMode: (id: String, isEnabled: Bool)?
    var currentConversationCallCount = 0
    var loadMessagesCallCount = 0

    init(
        currentConversation: ConversationRecord? = nil,
        loadedMessages: [ChatMessage] = [],
        createdConversation: ConversationRecord = ConversationRecord(
            id: UUID().uuidString,
            title: "New Chat",
            isPinned: false,
            uncensoredMode: false,
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

    func createConversation(title: String, uncensoredMode: Bool) throws -> ConversationRecord {
        createdConversationStub.uncensoredMode = uncensoredMode
        return createdConversationStub
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

    func setConversationUncensoredMode(id: String, isEnabled: Bool) throws -> ConversationSummary? {
        lastSetConversationUncensoredMode = (id, isEnabled)
        guard let currentConversationStub, currentConversationStub.id == id else {
            return nil
        }
        self.currentConversationStub?.uncensoredMode = isEnabled
        return ConversationSummary(
            id: currentConversationStub.id,
            title: currentConversationStub.title,
            isPinned: currentConversationStub.isPinned,
            uncensoredMode: isEnabled,
            createdAt: currentConversationStub.createdAt,
            updatedAt: currentConversationStub.updatedAt
        )
    }
}

@MainActor
private final class FakeAgentLoop: ChatSessionAgentLooping {
    var toolActivity: [AgentLoop.ToolLogEntry] = []
    var onProcess: ((String, [OllamaMessage], String, Bool) async throws -> [OllamaMessage])?

    func process(userMessage: String, history: [OllamaMessage], conversationId: String, uncensoredMode: Bool) async throws -> [OllamaMessage] {
        if let onProcess {
            return try await onProcess(userMessage, history, conversationId, uncensoredMode)
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
