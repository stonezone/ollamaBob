import Foundation

// MARK: - AgentLoop / Generic Continuation Guard
//
// Catches the "announce-and-stop" failure mode: the model emits a
// future-action sentence ("Now running nmap against 192.168.1.1", "Let me
// run that for you", "I'll check the routing table") as the FINAL
// assistant text, but never emits a tool_call. The loop sees no tool
// calls in the response and terminates the turn cleanly — leaving the
// user staring at a half-finished promise.
//
// This is the generic counterpart to AgentLoopBatchGuard.shouldForce-
// BatchAudioContinuation. The batch-audio guard is scoped to long
// audio-batch loops and trips on "next up..." status replies; this
// generic guard fires for ANY turn where the assistant ended with
// "I'll do X" but didn't.
//
// Design choices:
//   - Strictly `static` like the batch guard so callers stay
//     `AgentLoop.shouldForceContinuation(...)` and the orchestration
//     core stays focused.
//   - Cap nudges hard (default 1). If the model emits the same broken
//     pattern after one nudge, we give up rather than spin — a stuck
//     turn is better surfaced to the user than retried indefinitely.
//   - Refuses to fire when the last tool failed: pushing harder won't
//     help; the model needs to recover or surface the error, not
//     blindly retry.
//   - Refuses to fire on empty content: that's a different failure
//     mode (the batch guard handles status-only/empty for batch turns).
//   - Distinguishes "I'll do X" (action commitment Bob owes) from
//     "let me know what you want" (Bob handing the floor to the user)
//     to avoid nudging Bob to call a tool when he was actually asking
//     a clarifying question.
extension AgentLoop {

    /// True when the assistant's FINAL non-tool-call turn ends with a
    /// future-action announcement and we should nudge Bob to actually
    /// call the tool he just promised. Caller is responsible for only
    /// invoking this when `toolCalls` is empty/nil.
    static func shouldForceContinuation(
        assistantContent: String,
        lastToolResult: ToolResult?,
        nudgeCount: Int
    ) -> Bool {
        guard nudgeCount < AppConfig.continuationNudgeMax else { return false }
        // If the previous tool failed, the model needs space to recover or
        // explain. Don't push.
        if let lastToolResult, lastToolResult.success == false { return false }

        let trimmed = assistantContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        return endsWithFutureActionAnnouncement(trimmed)
    }

    /// Synthetic system message injected into the next loop iteration when
    /// the guard fires. Echoes a short slice of what Bob said so the
    /// nudge is concrete, then explicitly tells Bob to call the tool.
    static func continuationNudge(for assistantContent: String) -> String {
        let preview = assistantContent
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(240)
        return """
        Your previous reply ended with: "\(preview)"
        You announced a next action but did not call the tool that performs it. Call the tool now in this turn, or send a final answer that does not promise an unfinished action. Do not narrate intent without acting on it.
        """
    }

    // MARK: - Private detection

    /// Returns true if the LAST sentence of the content looks like an
    /// uncalled-action commitment. Conservative on purpose: prefer
    /// false negatives over false positives — a missed nudge wastes a
    /// turn, but a wrong nudge confuses the model and burns a
    /// continuation slot.
    ///
    /// Restricting matches to the FINAL sentence (not the whole trailing
    /// window) is what keeps idiomatic "running every now and then" and
    /// "I tried running it now and got the result. The output was 42."
    /// from false-positive — both contain the trigger phrase but neither
    /// ENDS with an unkept promise.
    private static func endsWithFutureActionAnnouncement(_ content: String) -> Bool {
        let normalized = content
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        // Extract the last sentence. Split on sentence-terminators
        // (. ! ?) followed by whitespace or end-of-string. Fall back
        // to the whole message if no terminator found.
        let lastSentence = lastSentenceOf(normalized)

        // Reject "I'm asking the user" / "let me know" patterns first —
        // those are the model legitimately turning the floor over.
        let userTurnoverMarkers = [
            "let me know",
            "let me know which",
            "let me know if",
            "let me know what",
            "let me know how",
            "let me know when",
            "let me know where",
            "let me know whether",
            "i need to ask",
            "i'll need to ask",
            "ill need to ask",
            "i would need to ask",
            "could you tell me",
            "can you tell me",
            "what do you want",
            "which do you want",
            "do you want me to",
        ]
        if userTurnoverMarkers.contains(where: { normalized.contains($0) }) {
            return false
        }

        // From here on, only look at the LAST sentence so a phrase
        // earlier in the message followed by a substantive answer
        // doesn't false-positive ("Let me check what I know. The
        // answer is 42." → must NOT fire).

        // Future-action commitment patterns. Each one is a phrase the
        // model uses immediately before performing an action. If any
        // appears in the trailing window, we treat it as an uncalled
        // promise. Past tense ("ran", "called") deliberately excluded.
        let actionCommitmentMarkers = [
            // "Now running X", "Now calling X", "Now, running X"
            "now running",
            "now, running",
            "now calling",
            "now, calling",
            "now invoking",
            "now, invoking",
            "now trying",
            "now, trying",
            "now executing",
            "now, executing",
            // "Running X now"
            "running it now",
            "running that now",
            "running the command now",
            // "Let me run/call/check/try/use/execute X"
            "let me run",
            "let me call",
            "let me check",
            "let me try",
            "let me use",
            "let me execute",
            "let me invoke",
            "let me grab",
            "let me fetch",
            "let me look",
            // "I'll run/call/check/try/use X"
            "i'll run",
            "ill run",
            "i will run",
            "i'll call",
            "ill call",
            "i will call",
            "i'll check",
            "ill check",
            "i will check",
            "i'll try",
            "ill try",
            "i will try",
            "i'll use",
            "ill use",
            "i will use",
            "i'll execute",
            "ill execute",
            "i will execute",
            "i'll grab",
            "ill grab",
            "i'll fetch",
            "ill fetch",
            "i'll look",
            "ill look",
            "i'll go",
            "ill go ahead",
        ]

        if actionCommitmentMarkers.contains(where: { lastSentence.contains($0) }) {
            return true
        }

        // "Running <X> now" / "Running <X> now." — common Gemma trailing
        // construction ("Running brew upgrade now.", "Running nmap now.").
        // Anchored: `now` must be at the END of the last sentence
        // (i.e., end of the extracted slice). This rejects "running
        // every now and then" and "running it now and getting result"
        // while still catching the real announce-and-stop case.
        // Trailing punctuation (`.` `!` `…`) is allowed after `now`
        // so "Running brew upgrade now." matches but "running every
        // now and then" does not.
        if lastSentence.range(
            of: #"\brunning\b(?:\s+\S+){1,5}\s+now\b[\.\!\?…]*\s*$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        return false
    }

    /// Returns the trailing sentence of `content`. Splits on `.`/`!`/`?`
    /// followed by whitespace or end-of-string. If no terminator
    /// appears in the trailing 240 chars, returns the trailing 240
    /// chars unchanged. Operates on already-normalized lowercase text.
    private static func lastSentenceOf(_ normalized: String) -> String {
        // Look only at the trailing 240 chars — anything earlier is too
        // far back to be the model's "final commitment".
        let window = String(normalized.suffix(240))

        guard let regex = try? NSRegularExpression(pattern: #"[.!?](?:\s+|$)"#) else {
            return window
        }
        let range = NSRange(window.startIndex..., in: window)
        let matches = regex.matches(in: window, range: range)
        guard let lastTerminator = matches.dropLast().last,
              let terminatorRange = Range(lastTerminator.range, in: window) else {
            // 0 or 1 terminators → whole window IS the last sentence
            // (the trailing terminator, if any, just closes it).
            return window.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(window[terminatorRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
