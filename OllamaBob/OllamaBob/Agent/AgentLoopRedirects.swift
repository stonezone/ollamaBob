import Foundation

// MARK: - AgentLoop / Tool Intent Redirects
//
// Phase 2a (peer-review plan, 2026-04-28): split out of
// AgentLoopToolDispatch.swift to keep each coordinator file under the
// 600 LOC ceiling.
//
// Scope of this file: small policy nudges that catch a tool call whose
// shape doesn't match the user's actual intent and redirect it to a
// better-fit tool (or refuse, if the better-fit tool is disabled).
//
//   - `read_file` for an "open in default app" intent → guide to `present` (or shell `open`).
//   - `present` when rich presentation is disabled → guide to shell `open`.
//   - `applescript` for a simple open intent → guide to shell `open`.
//
// `shouldRedirectReadFileToPresent` and `shouldRedirectAppleScriptOpenToShell`
// stay public-on-AgentLoop because tests reference them directly.
extension AgentLoop {

    func redirectedReadFileOpenIntentIfNeeded(name: String, args: [String: Any]) -> ToolResult? {
        guard name == "read_file",
              let path = args["path"] as? String,
              let currentUserMessage,
              Self.shouldRedirectReadFileToPresent(userMessage: currentUserMessage, path: path) else {
            return nil
        }

        let guidance: String
        if AppSettings.shared.richPresentationEnabled {
            guidance = "User asked to open a local file in its default app, not to read its contents into chat. Use present with kind='file' and content='\(path)' instead of read_file. If present returns 'path not allowed', relay that refusal to the user."
        } else {
            guidance = "User asked to open a local file in its default app, not to read its contents into chat. Rich presentation is disabled, so do not use read_file here. Use shell with macOS open if appropriate, or explain that you cannot open it."
        }

        return .failure(tool: "read_file", error: guidance, durationMs: 0)
    }

    func redirectedDisabledPresentToolIfNeeded(name: String, args: [String: Any]) -> ToolResult? {
        guard name == "present",
              AppSettings.shared.richPresentationEnabled == false,
              let currentUserMessage else {
            return nil
        }

        let lower = currentUserMessage.lowercased()
        let openIntent = ["open ", "launch ", "show ", "in preview", "in browser", "default app", "proper window"]
            .contains { lower.contains($0) }
        guard openIntent else { return nil }

        let content = (args["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let kind = (args["kind"] as? String)?.lowercased() ?? ""

        let guidance: String
        if kind == "file" || content.hasPrefix("/") || content.hasPrefix("~") {
            guidance = "Rich presentation is disabled, so the present tool is unavailable. Use shell with macOS open for the file instead, or explain that you cannot open it."
        } else if kind == "url" || content.lowercased().hasPrefix("http://") || content.lowercased().hasPrefix("https://") {
            guidance = "Rich presentation is disabled, so the present tool is unavailable. Use shell with macOS open for the URL instead, or explain that you cannot open it."
        } else {
            guidance = "Rich presentation is disabled, so the present tool is unavailable. Use shell with macOS open for simple open/show requests, or explain that you cannot open it."
        }

        return .failure(tool: "present", error: guidance, durationMs: 0)
    }

    func redirectedAppleScriptOpenIntentIfNeeded(name: String, args: [String: Any]) -> ToolResult? {
        guard name == "applescript",
              let script = args["script"] as? String,
              let currentUserMessage,
              Self.shouldRedirectAppleScriptOpenToShell(userMessage: currentUserMessage, script: script) else {
            return nil
        }

        return .failure(
            tool: "applescript",
            error: "User asked to open a file or URL in its default app. Do not use applescript for that. Use shell with macOS open instead, or explain that you cannot open it.",
            durationMs: 0
        )
    }

    static func shouldRedirectReadFileToPresent(userMessage: String, path: String) -> Bool {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.hasPrefix("/") || trimmedPath.hasPrefix("~") else {
            return false
        }

        let lower = userMessage.lowercased()
        let openPhrases = [
            "open ",
            "launch ",
            "in preview",
            "preview ",
            "in browser",
            "in my browser",
            "default app"
        ]
        guard openPhrases.contains(where: { lower.contains($0) }) else {
            return false
        }

        let contentReadPhrases = [
            "contents of",
            "content of",
            "show me the contents",
            "paste the contents",
            "quote the contents",
            "summarize the file",
            "cat ",
            "head ",
            "tail ",
            "grep "
        ]
        return contentReadPhrases.contains(where: { lower.contains($0) }) == false
    }

    static func shouldRedirectAppleScriptOpenToShell(userMessage: String, script: String) -> Bool {
        let lowerMessage = userMessage.lowercased()
        let lowerScript = script.lowercased()
        let openIntent = ["open ", "launch ", "show ", "preview ", "in preview", "in browser", "default app"]
            .contains { lowerMessage.contains($0) }
        guard openIntent else { return false }

        let isSimpleOpenScript =
            lowerScript.contains(" to open file ") ||
            lowerScript.contains(" to open posix file") ||
            lowerScript.contains(" to open alias ") ||
            lowerScript.contains(" to open location ") ||
            lowerScript.contains("tell application \"finder\" to open ") ||
            lowerScript.contains("open location ")

        let automationIntent = ["finder automation", "system events", "click", "select", "reveal in finder"]
            .contains { lowerMessage.contains($0) }

        return isSimpleOpenScript && automationIntent == false
    }
}
