import XCTest
@testable import OllamaBob

@MainActor
final class DeskViewModelTests: XCTestCase {
    override func tearDown() {
        DeskPromptInbox.shared.resetForTesting()
        super.tearDown()
    }

    func testDeskViewModelDrainsPendingPromptsOnAppear() {
        let session = FakeDeskSession()
        let inbox = FakeDeskPromptInbox(prompts: ["one", "two"])
        let model = DeskViewModel(
            session: session,
            agent: FakeDeskAgent(isProcessing: false),
            inbox: inbox,
            notificationCenter: NotificationCenter()
        )

        model.drainPendingDeskPrompts()

        XCTAssertEqual(inbox.drainCount, 1)
        XCTAssertEqual(session.inputText, "two")
        XCTAssertEqual(session.sendCount, 2)
        XCTAssertNotNil(model.inputFocusRequestID)

        let externalSession = FakeDeskSession()
        let externalModel = DeskViewModel(
            session: externalSession,
            agent: FakeDeskAgent(isProcessing: false),
            inbox: FakeDeskPromptInbox(prompts: ["external"]),
            sendsViaExternalHandler: true,
            notificationCenter: NotificationCenter()
        )

        externalModel.drainPendingDeskPrompts()

        XCTAssertEqual(externalSession.inputText, "external")
        XCTAssertEqual(externalSession.sendCount, 0)
        XCTAssertNotNil(externalModel.inputFocusRequestID)
        XCTAssertNotNil(externalModel.sendPromptRequestID)
    }

    func testDeskViewModelPreservesMultipleExternallyHandledPrompts() {
        let session = FakeDeskSession()
        let model = DeskViewModel(
            session: session,
            agent: FakeDeskAgent(isProcessing: false),
            inbox: FakeDeskPromptInbox(prompts: ["first", "second"]),
            sendsViaExternalHandler: true,
            notificationCenter: NotificationCenter()
        )

        model.drainPendingDeskPrompts()

        XCTAssertTrue(model.prepareNextExternallyHandledPromptForSend())
        session.sendCurrentInput(allowsLocalCommands: true)
        XCTAssertFalse(model.prepareNextExternallyHandledPromptForSend())

        model.externallyHandledPromptDidFinish()
        XCTAssertTrue(model.prepareNextExternallyHandledPromptForSend())
        session.sendCurrentInput(allowsLocalCommands: true)

        XCTAssertEqual(session.sentInputs, ["first", "second"])
        XCTAssertFalse(model.prepareNextExternallyHandledPromptForSend())
    }

    func testDeskViewModelStageOrSendInjectedPromptDoesNotSendWhenAgentBusy() {
        let session = FakeDeskSession()
        let model = DeskViewModel(
            session: session,
            agent: FakeDeskAgent(isProcessing: true),
            inbox: FakeDeskPromptInbox(),
            notificationCenter: NotificationCenter()
        )

        model.stageOrSendInjectedPrompt("hello")

        XCTAssertEqual(session.inputText, "hello")
        XCTAssertEqual(session.sendCount, 0)
        XCTAssertNotNil(model.inputFocusRequestID)

        let externalSession = FakeDeskSession()
        let externalModel = DeskViewModel(
            session: externalSession,
            agent: FakeDeskAgent(isProcessing: true),
            inbox: FakeDeskPromptInbox(),
            sendsViaExternalHandler: true,
            notificationCenter: NotificationCenter()
        )

        externalModel.stageOrSendInjectedPrompt("busy")

        XCTAssertEqual(externalSession.inputText, "busy")
        XCTAssertEqual(externalSession.sendCount, 0)
        XCTAssertNotNil(externalModel.inputFocusRequestID)
        XCTAssertNil(externalModel.sendPromptRequestID)
    }

    func testDeskViewModelHistoryOverlayToggle() {
        let center = NotificationCenter()
        let model = DeskViewModel(
            session: FakeDeskSession(),
            agent: FakeDeskAgent(isProcessing: false),
            inbox: FakeDeskPromptInbox(),
            notificationCenter: center
        )

        XCTAssertFalse(model.showHistoryOverlay)
        center.post(name: .bobToggleHistoryOverlay, object: nil)
        XCTAssertTrue(model.showHistoryOverlay)
        center.post(name: .bobToggleHistoryOverlay, object: nil)
        XCTAssertFalse(model.showHistoryOverlay)
    }

    func testDeskViewModelDrainsWhenDeskPromptAvailableNotificationPosts() {
        let center = NotificationCenter()
        let session = FakeDeskSession()
        let inbox = FakeDeskPromptInbox(prompts: ["queued"])
        let model = DeskViewModel(
            session: session,
            agent: FakeDeskAgent(isProcessing: false),
            inbox: inbox,
            notificationCenter: center
        )

        center.post(name: .bobDeskPromptAvailable, object: nil)

        XCTAssertEqual(inbox.drainCount, 1)
        XCTAssertEqual(session.inputText, "queued")
        XCTAssertEqual(session.sendCount, 1)
        XCTAssertNotNil(model.inputFocusRequestID)
    }

    func testDeskViewModelHandlesWalkieTalkieTranscript() {
        let center = NotificationCenter()
        let session = FakeDeskSession()
        let model = DeskViewModel(
            session: session,
            agent: FakeDeskAgent(isProcessing: false),
            inbox: FakeDeskPromptInbox(),
            notificationCenter: center
        )
        XCTAssertFalse(model.showHistoryOverlay)

        center.post(name: .bobWalkieTalkieTranscript, object: nil, userInfo: ["transcript": "  test me  "])

        XCTAssertEqual(session.inputText, "test me")
        XCTAssertEqual(session.sendCount, 1)
    }

    func testDeskViewModelHandlesClipboardStackTraceRequest() {
        let center = NotificationCenter()
        let session = FakeDeskSession()
        let model = DeskViewModel(
            session: session,
            agent: FakeDeskAgent(isProcessing: false),
            inbox: FakeDeskPromptInbox(),
            notificationCenter: center
        )

        center.post(name: .clipboardCortexSummarizeStackTrace, object: nil, userInfo: ["content": "Error\n at frame"])

        XCTAssertTrue(session.inputText.contains("Summarize this stack trace"), session.inputText)
        XCTAssertTrue(session.inputText.contains(UntrustedWrapper.openTag), session.inputText)
        XCTAssertEqual(session.sendCount, 1)
        XCTAssertNotNil(model.chatOpenRequestID)

        let busyCenter = NotificationCenter()
        let busySession = FakeDeskSession()
        let busyModel = DeskViewModel(
            session: busySession,
            agent: FakeDeskAgent(isProcessing: true),
            inbox: FakeDeskPromptInbox(),
            sendsViaExternalHandler: true,
            notificationCenter: busyCenter
        )

        busyCenter.post(name: .clipboardCortexSummarizeStackTrace, object: nil, userInfo: ["content": "Error\n at frame"])

        XCTAssertTrue(busySession.inputText.contains("Summarize this stack trace"), busySession.inputText)
        XCTAssertTrue(busySession.inputText.contains(UntrustedWrapper.openTag), busySession.inputText)
        XCTAssertEqual(busySession.sendCount, 0)
        XCTAssertNotNil(busyModel.inputFocusRequestID)
        XCTAssertNotNil(busyModel.chatOpenRequestID)
        XCTAssertNil(busyModel.sendPromptRequestID)
    }
}

private final class FakeDeskSession: DeskSessionControlling {
    var inputText = ""
    private(set) var sendCount = 0
    private(set) var sentInputs: [String] = []

    func sendCurrentInput(allowsLocalCommands: Bool) {
        sendCount += 1
        sentInputs.append(inputText)
    }
}

private final class FakeDeskAgent: DeskAgentProcessing {
    var isProcessing: Bool

    init(isProcessing: Bool) {
        self.isProcessing = isProcessing
    }
}

private final class FakeDeskPromptInbox: DeskPromptInboxing {
    private var prompts: [String]
    private(set) var drainCount = 0

    init(prompts: [String] = []) {
        self.prompts = prompts
    }

    func drain() -> [String] {
        drainCount += 1
        let drained = prompts
        prompts.removeAll()
        return drained
    }
}
