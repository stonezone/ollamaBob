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

        // v1.0.48: track-list detection. Catches the case where the user
        // pastes a multi-line list of "Song — Artist" pairs (or "Song -
        // Artist") and asks for them, even when the action verb is
        // misspelled ("downlaod"), missing entirely, or replaced with a
        // colloquial one we don't enumerate. 3+ list lines + at least
        // one music/youtube keyword anywhere in the message is a strong
        // signal: this is a music-batch turn, give it the longer budget
        // so the batch-audit continuation guard can actually fire.
        let listLines = userMessage.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line -> Bool in
                guard line.count >= 5, line.count <= 200 else { return false }
                // em-dash, en-dash, or hyphen-with-spaces all count.
                return line.contains(" — ") || line.contains(" – ") || line.contains(" - ")
            }
        let musicKeywordPresent = ["mp3", "m4a", "flac", "song", "track",
                                   "album", "playlist", "youtube", "youtu.be"]
            .contains { normalized.contains($0) }
        let hasPastedTrackList = listLines.count >= 3 && musicKeywordPresent

        if isAudioBatch || isListedTrackBatch || hasPastedTrackList {
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
