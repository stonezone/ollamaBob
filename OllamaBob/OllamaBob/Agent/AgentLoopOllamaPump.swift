import Foundation

// MARK: - AgentLoop / Ollama Pump
//
// Phase 2a (peer-review plan, 2026-04-28): extracted from AgentLoop.swift.
// Owns model selection per turn, the consecutive-failure → fallback-model
// switch, and the per-message loop-budget classifier.
//
// `loopBudget(for:)` is `static` and visible to tests as
// `AgentLoop.loopBudget(...)`. `checkFallback` and
// `updateCurrentModelForTurn` are instance methods that mutate
// `@MainActor` state on `AgentLoop`; their visibility is preserved.
extension AgentLoop {

    // MARK: - Loop budget classifier

    static func loopBudget(for userMessage: String) -> LoopBudget {
        let normalized = userMessage
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        let actionTerms = [
            "download", "get", "save", "rip", "convert", "transcode",
            "grab", "fetch", "pull", "collect"
        ]
        let audioTerms = [
            "album", "albums", "playlist", "song", "songs", "track", "tracks",
            "mp3", "m4a", "flac", "audio", "music"
        ]
        let isAudioBatch = actionTerms.contains { normalized.contains($0) }
            && audioTerms.contains { normalized.contains($0) }
        let isListedTrackBatch = normalized.contains("all these")
            && (normalized.contains("track") || normalized.contains("song"))

        if isAudioBatch || isListedTrackBatch {
            return LoopBudget(
                maxIterations: AppConfig.batchAudioAgentLoopMaxIterations,
                timeoutSeconds: AppConfig.batchAudioAgentLoopTimeoutSeconds
            )
        }

        return LoopBudget(
            maxIterations: AppConfig.agentLoopMaxIterations,
            timeoutSeconds: AppConfig.agentLoopTimeoutSeconds
        )
    }

    // MARK: - Model fallback

    func checkFallback() async {
        guard currentUncensoredMode == false else { return }
        if consecutiveFailures >= AppConfig.maxConsecutiveFailures && currentModel != AppConfig.fallbackModel {
            let oldModel = currentModel
            currentModel = AppConfig.fallbackModel
            consecutiveFailures = 0
            modelSwitchNotice = ModelSwitchNotice(from: oldModel, to: currentModel, at: Date())
            if let handler = modelSwitchHandler {
                await handler(oldModel, currentModel)
            }
        }
    }

    func updateCurrentModelForTurn(_ model: String, notify: Bool) async {
        guard currentModel != model else { return }
        let oldModel = currentModel
        currentModel = model
        guard notify else { return }
        modelSwitchNotice = ModelSwitchNotice(from: oldModel, to: model, at: Date())
        if let handler = modelSwitchHandler {
            await handler(oldModel, model)
        }
    }
}
