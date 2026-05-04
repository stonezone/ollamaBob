import Foundation

/// Background heartbeat that polls Ollama's `/api/ps` endpoint while the
/// app is awaiting a `/api/chat` response. v1.0.52.
///
/// Why this exists: with `stream: false`, Ollama buffers the entire
/// generation server-side and sends it as one HTTP response at the end.
/// During generation the client gets ZERO bytes, so URLSession's idle
/// timeout never trips — and from the user's POV Bob looks identical to
/// "thinking" or "wedged" or "Ollama silently died". This heartbeat
/// solves that by independently asking Ollama "what's loaded right now?"
/// every few seconds; the answer is cheap (`/api/ps` is a tiny GET) and
/// tells us:
///
///   - The requested model IS loaded → Ollama is genuinely processing.
///   - The requested model IS NOT loaded → Either it never loaded
///     (rare; load failure) or it loaded then unloaded mid-request
///     (the wedge mode the user hit on a 166-msg context — Ollama
///     stops processing but keeps the TCP socket open). In either
///     case the chat call is not going to finish on its own.
///   - The model loaded just now (was absent then present) → still
///     in the model-load phase; we should be patient.
///
/// Threading: the heartbeat is a single `Task` started by AgentLoop
/// when it fires `client.chat()`. AgentLoop also captures the start
/// time so wall-clock thresholds can be checked alongside model
/// presence. The heartbeat publishes `WaitState` updates back to
/// AgentLoop via a closure (no shared mutable state).
///
/// Cancel: the wrapping `Task` is cancelled when the chat call returns
/// (success or failure), or when the user hits ⌘. The heartbeat
/// respects `Task.isCancelled` between polls.
@MainActor
final class OllamaHeartbeat {
    private let baseURL: String
    private let pollInterval: TimeInterval
    private let session: URLSession

    /// `nil` when not running.
    private var task: Task<Void, Never>?

    init(
        baseURL: String = AppConfig.ollamaBaseURL,
        pollInterval: TimeInterval = AppConfig.ollamaHeartbeatIntervalSeconds
    ) {
        self.baseURL = baseURL
        self.pollInterval = pollInterval
        // Short timeout per poll — these are tiny GETs; if /api/ps
        // takes more than a couple seconds something is genuinely
        // wrong with Ollama itself.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        self.session = URLSession(configuration: config)
    }

    /// Start polling. `onUpdate` is called on the MainActor with each
    /// fresh sample. `requestedModel` is the model the chat call is
    /// using; we compare it against `/api/ps` to detect drop-out.
    /// Idempotent — calling `start` while already running cancels the
    /// previous task first.
    func start(
        requestedModel: String,
        startedAt: Date,
        onUpdate: @escaping @MainActor (HeartbeatSample) -> Void
    ) {
        stop()
        let captured = (baseURL: baseURL,
                        interval: pollInterval,
                        session: session,
                        model: requestedModel,
                        startedAt: startedAt)
        task = Task { @MainActor [weak self] in
            var previouslyLoaded = false
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(captured.startedAt)
                let snapshot = await Self.pollOnce(
                    session: captured.session,
                    baseURL: captured.baseURL
                )
                let nowLoaded = snapshot.contains(where: { $0.name == captured.model })
                let dropped = previouslyLoaded && !nowLoaded
                let sample = HeartbeatSample(
                    elapsedSeconds: elapsed,
                    requestedModelLoaded: nowLoaded,
                    requestedModelDroppedMidRequest: dropped,
                    loadedModels: snapshot
                )
                onUpdate(sample)
                previouslyLoaded = previouslyLoaded || nowLoaded
                guard self != nil else { return }
                // Sleep returns early if cancelled, so the loop is
                // responsive to stop().
                try? await Task.sleep(nanoseconds: UInt64(captured.interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: - Poll

    /// Single `/api/ps` call. Returns the parsed model list; on any
    /// failure (network, parse, non-200) returns empty. We deliberately
    /// don't throw — heartbeat failure is informational, not fatal.
    private static func pollOnce(
        session: URLSession,
        baseURL: String
    ) async -> [LoadedModel] {
        guard let url = URL(string: baseURL + "/api/ps") else { return [] }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            let decoded = try JSONDecoder().decode(PSResponse.self, from: data)
            return decoded.models
        } catch {
            return []
        }
    }

    // MARK: - Types

    struct HeartbeatSample: Equatable, Sendable {
        let elapsedSeconds: TimeInterval
        let requestedModelLoaded: Bool
        /// True when the model WAS loaded on a prior poll and is no
        /// longer loaded now. Strong signal that Ollama dropped the
        /// request mid-flight.
        let requestedModelDroppedMidRequest: Bool
        let loadedModels: [LoadedModel]
    }

    struct LoadedModel: Decodable, Equatable, Sendable {
        let name: String
        let expiresAt: String?

        enum CodingKeys: String, CodingKey {
            case name
            case expiresAt = "expires_at"
        }
    }

    private struct PSResponse: Decodable {
        let models: [LoadedModel]
    }
}
