import Combine
import Foundation

@MainActor
protocol DeskSessionControlling: AnyObject {
    var inputText: String { get set }
    func sendCurrentInput(allowsLocalCommands: Bool)
}

@MainActor
protocol DeskAgentProcessing: AnyObject {
    var isProcessing: Bool { get }
}

@MainActor
protocol DeskPromptInboxing: AnyObject {
    func drain() -> [String]
}

extension ChatSessionController: DeskSessionControlling {}
extension AgentLoop: DeskAgentProcessing {}
extension DeskPromptInbox: DeskPromptInboxing {}

@MainActor
final class DeskViewModel: ObservableObject {
    @Published var bubbleVisible = false
    @Published var breathPhase = false
    @Published var awaitingTurnTranscript = false
    @Published var showHistoryOverlay = false
    @Published private(set) var inputFocusRequestID: UUID?
    @Published private(set) var chatOpenRequestID: UUID?
    @Published private(set) var sendPromptRequestID: UUID?

    private let session: DeskSessionControlling
    private let agent: DeskAgentProcessing
    private let inbox: DeskPromptInboxing
    private let sendsViaExternalHandler: Bool
    private let notificationCenter: NotificationCenter
    private var notificationObservers: [NSObjectProtocol] = []
    private var externallyHandledPromptQueue: [String] = []
    private var externallyHandledPromptInFlight = false

    init(
        session: DeskSessionControlling,
        agent: DeskAgentProcessing,
        inbox: DeskPromptInboxing? = nil,
        sendsViaExternalHandler: Bool = false,
        notificationCenter: NotificationCenter = .default
    ) {
        self.session = session
        self.agent = agent
        self.inbox = inbox ?? DeskPromptInbox.shared
        self.sendsViaExternalHandler = sendsViaExternalHandler
        self.notificationCenter = notificationCenter
        startNotificationObservers()
    }

    deinit {
        for observer in notificationObservers {
            notificationCenter.removeObserver(observer)
        }
    }

    func drainPendingDeskPrompts() {
        for prompt in inbox.drain() {
            stageOrSendInjectedPrompt(prompt)
        }
    }

    func stageOrSendInjectedPrompt(_ prompt: String) {
        session.inputText = prompt
        inputFocusRequestID = UUID()
        guard agent.isProcessing == false else { return }
        submitPrompt()
    }

    func prepareNextExternallyHandledPromptForSend() -> Bool {
        guard sendsViaExternalHandler,
              externallyHandledPromptInFlight == false,
              agent.isProcessing == false,
              externallyHandledPromptQueue.isEmpty == false else { return false }
        let prompt = externallyHandledPromptQueue.removeFirst()
        session.inputText = prompt
        inputFocusRequestID = UUID()
        externallyHandledPromptInFlight = true
        return true
    }

    func externallyHandledPromptDidFinish() {
        guard sendsViaExternalHandler else { return }
        externallyHandledPromptInFlight = false
        requestExternallyHandledPromptIfPossible()
    }

    func toggleHistoryOverlay() {
        showHistoryOverlay.toggle()
    }

    private func startNotificationObservers() {
        notificationObservers.append(
            notificationCenter.addObserver(
                forName: .bobToggleHistoryOverlay,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.toggleHistoryOverlay() }
            }
        )
        notificationObservers.append(
            notificationCenter.addObserver(
                forName: .bobWalkieTalkieTranscript,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated { self?.handleWalkieTalkieTranscript(notification) }
            }
        )
        notificationObservers.append(
            notificationCenter.addObserver(
                forName: .clipboardCortexSummarizeStackTrace,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated { self?.handleClipboardStackTraceRequest(notification) }
            }
        )
        notificationObservers.append(
            notificationCenter.addObserver(
                forName: .bobDeskPromptAvailable,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.drainPendingDeskPrompts() }
            }
        )
    }

    private func handleWalkieTalkieTranscript(_ notification: Notification) {
        guard let prompt = DeskPromptActions.walkieTalkiePrompt(from: notification) else { return }
        stageOrSendInjectedPrompt(prompt)
    }

    private func handleClipboardStackTraceRequest(_ notification: Notification) {
        guard let prompt = DeskPromptActions.stackTracePrompt(from: notification) else { return }
        stageOrSendInjectedPrompt(prompt)
        chatOpenRequestID = UUID()
    }

    private func submitPrompt() {
        if sendsViaExternalHandler {
            externallyHandledPromptQueue.append(session.inputText)
            requestExternallyHandledPromptIfPossible()
        } else {
            session.sendCurrentInput(allowsLocalCommands: true)
        }
    }

    private func requestExternallyHandledPromptIfPossible() {
        guard sendsViaExternalHandler,
              externallyHandledPromptInFlight == false,
              agent.isProcessing == false,
              externallyHandledPromptQueue.isEmpty == false else { return }
        sendPromptRequestID = UUID()
    }

}
