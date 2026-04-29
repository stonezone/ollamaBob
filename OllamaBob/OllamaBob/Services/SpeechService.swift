import Foundation
import AVFoundation
import Speech
import Combine

// MARK: - SpeechServiceState

/// Externally-observable recording / synthesis state.
enum SpeechServiceState: Equatable {
    case idle
    case recording
    case speaking
}

// MARK: - SpeechService

/// Singleton that owns microphone capture (via SFSpeechRecognizer +
/// AVAudioEngine) and speech synthesis (via AVSpeechSynthesizer).
///
/// Push-to-talk contract:
///   • call `startRecording()` on key-down
///   • call `stopRecording()` on key-up
///   • subscribe to `transcriptPublisher` to receive the final transcript
///
/// All operations fail-closed when TCC authorisation is missing.
@MainActor
final class SpeechService: ObservableObject {

    static let shared = SpeechService()

    // MARK: Published state

    @Published private(set) var state: SpeechServiceState = .idle

    /// Emits the final transcript after `stopRecording()` completes.
    /// An empty string is never emitted.
    let transcriptPublisher = PassthroughSubject<String, Never>()

    // MARK: Private audio/speech objects

    private var recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let synthesizer = AVSpeechSynthesizer()

    // Accumulates partial results while recording.
    private var partialTranscript: String = ""

    // MARK: Init

    private init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Authorization

    /// Returns `true` when both speech recognition and microphone TCC have
    /// already been granted.  Does NOT trigger any permission prompts.
    nonisolated func isAuthorized() -> Bool {
        let speechOK = SFSpeechRecognizer.authorizationStatus() == .authorized
        let micOK = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        return speechOK && micOK
    }

    /// Requests both speech and microphone permissions in sequence.
    /// Returns `true` only when both are granted.
    func requestAuthorization() async -> Bool {
        // Speech recognition
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }

        // Microphone (AVCaptureDevice on macOS)
        let micStatus = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        return micStatus
    }

    // MARK: - Recording

    /// Begin capturing audio and running on-device speech recognition.
    /// Silently no-ops if already recording or if authorisation is missing.
    func startRecording() {
        guard state == .idle else { return }
        guard isAuthorized() else { return }
        guard let recognizer, recognizer.isAvailable else { return }

        partialTranscript = ""

        do {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // Prefer on-device recognition when available.
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    Task { @MainActor in
                        self.partialTranscript = result.bestTranscription.formattedString
                    }
                }
                if error != nil || result?.isFinal == true {
                    Task { @MainActor in
                        self.finalizeRecording()
                    }
                }
            }

            state = .recording
        } catch {
            stopAudioEngine()
        }
    }

    /// Stop capturing audio and finalize the transcript.
    /// Silently no-ops if not currently recording.
    func stopRecording() {
        guard state == .recording else { return }
        recognitionRequest?.endAudio()
        stopAudioEngine()
        finalizeRecording()
    }

    // MARK: - Synthesis

    /// Speak `text` via `AVSpeechSynthesizer`.
    /// Empty strings are silently discarded (no-op).
    ///
    /// - Parameter text: The string to synthesize.
    /// - Parameter languageCode: BCP-47 tag; defaults to `"en-US"`.
    func speak(_ text: String, languageCode: String = "en-US") {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
            ?? AVSpeechSynthesisVoice(language: "en-US")

        // If already speaking, stop gracefully and start the new utterance.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }

        state = .speaking
        synthesizer.speak(utterance)

        // Monitor completion on a background task to reset state.
        Task {
            await waitForSynthesizerToFinish()
            if state == .speaking {
                state = .idle
            }
        }
    }

    /// Stop any in-progress synthesis.
    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if state == .speaking {
            state = .idle
        }
    }

    // MARK: - Private helpers

    private func finalizeRecording() {
        stopAudioEngine()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        let transcript = partialTranscript
        partialTranscript = ""

        if state == .recording {
            state = .idle
        }

        if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            transcriptPublisher.send(transcript)
        }
    }

    private func stopAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    /// Poll the synthesizer's `isSpeaking` property until it finishes.
    /// AVSpeechSynthesizerDelegate would be cleaner but requires a delegate
    /// object; this keeps the service self-contained.
    private func waitForSynthesizerToFinish() async {
        while synthesizer.isSpeaking {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms
        }
    }
}
