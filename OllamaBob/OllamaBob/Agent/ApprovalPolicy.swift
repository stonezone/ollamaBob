import Foundation

enum ApprovalPolicy {
    /// Determine the approval level for a tool call.
    static func check(toolName: String, arguments: [String: Any]) -> ApprovalLevel {
        let base = baseCheck(toolName: toolName, arguments: arguments)
        let afterOverride = applyUserOverride(toolName: toolName, arguments: arguments, base: base)
        return applyDevModeDowngrade(toolName: toolName, arguments: arguments, level: afterOverride)
    }

    // MARK: - Dev Mode downgrade (Phase 6)

    /// If Code Companion dev mode is active and the tool is `write_file` with
    /// a path inside the stored repo root, downgrade `.modal` to `.none`.
    /// `shell` is NEVER downgraded — the repo root provides no safety boundary
    /// for arbitrary shell commands.
    ///
    /// Reads `DevModeStore.shared.currentRepoRoot` via a thread-safe
    /// `NSLock`-backed accessor. Safe to call from any actor or thread.
    /// `shell` is NEVER downgraded — it has no per-repo safety boundary.
    private static func applyDevModeDowngrade(
        toolName: String,
        arguments: [String: Any],
        level: ApprovalLevel
    ) -> ApprovalLevel {
        // Only `write_file` qualifies — shell is never auto-approved.
        guard toolName == "write_file", level == .modal else { return level }

        let repoRoot = DevModeStorage.shared.get()

        guard let repoRoot, !repoRoot.isEmpty else { return level }

        guard let rawPath = arguments["path"] as? String,
              let resolved = FileToolPaths.resolvedURL(for: rawPath) else {
            return level
        }

        let normalizedRoot = (repoRoot as NSString).expandingTildeInPath
        let standardizedRoot = URL(fileURLWithPath: normalizedRoot)
            .standardizedFileURL.path
        let standardizedPath = resolved.standardizedFileURL.path

        // Path must start with root + "/" to prevent the prefix-attack where
        // repoRoot="/tmp/foo" would incorrectly match path="/tmp/foobar/x.txt".
        guard standardizedPath == standardizedRoot ||
              standardizedPath.hasPrefix(standardizedRoot + "/") else {
            return level
        }

        return .none
    }

    private static func baseCheck(toolName: String, arguments: [String: Any]) -> ApprovalLevel {
        switch toolName {
        case "read_file":
            let path = arguments["path"] as? String ?? ""
            return pathToApproval(path, defaultForAllowed: .none)

        case "create_directory":
            let path = arguments["path"] as? String ?? ""
            return structuredWriteApproval(path)

        case "list_directory":
            let path = arguments["path"] as? String ?? ""
            return structuredReadApproval(path)

        case "write_file":
            let path = arguments["path"] as? String ?? ""
            return structuredWriteApproval(path)

        case "move_file":
            let source = arguments["source"] as? String ?? ""
            let destination = arguments["destination"] as? String ?? ""
            return structuredMoveApproval(source: source, destination: destination)

        case "git_status":
            let repoPath = arguments["repo_path"] as? String ?? ""
            return structuredReadApproval(repoPath)

        case "git_diff":
            let repoPath = arguments["repo_path"] as? String ?? ""
            return structuredReadApproval(repoPath)

        case "search_files":
            let path = arguments["path"] as? String ?? NSHomeDirectory()
            return pathToApproval(path, defaultForAllowed: .none)

        case "phone_call":
            return .modal

        case "phone_hangup":
            return .none

        case "phone_status":
            return .none

        // Phase 4a — call supervision tools
        case "phone_list_calls":
            // Read-only list of active calls — no approval needed.
            return .none

        case "phone_get_transcript":
            // Read-only transcript fetch — no approval needed.
            return .none

        case "phone_inject":
            // Side-effecting: injects text into an active call — always ask.
            return .modal

        case "web_search":
            return .none

        case "mail_check":
            // Mail metadata is private even when read-only. Always ask.
            return .modal

        case "mail_triage":
            // Message previews are sensitive even when read-only. Always ask.
            return .modal

        case "present":
            return .none

        case "read_tool_output":
            // Reads a file Bob himself wrote during this conversation,
            // under OllamaBob's own app support dir. No user-visible
            // side effects, no approval required.
            return .none

        case "tool_help":
            // Pure in-memory lookup against the bundled ToolCatalog.
            // No filesystem, no network, no shell. Never approve.
            return .none

        case "remember":
            // Writing to the facts DB. No external side effects but
            // the user might not want Bob auto-remembering things, so
            // keep it silent (the user told Bob to remember it in
            // the first place). No approval needed.
            return .none

        case "list_facts":
            // Pure read from the local facts DB. No approval.
            return .none

        case "forget":
            // Deleting a fact. V2 plan says modal approval so the
            // user can see what Bob is about to delete.
            return .modal

        case "clipboard_read":
            // Reading what the user already put there themselves.
            return .none

        case "clipboard_write":
            // Silently replaces whatever the user had copied — always ask.
            return .modal

        case "applescript":
            // Can touch any scriptable app. Always ask, even for read-only
            // scripts — the user should see the source before it runs.
            return .modal

        case "speak":
            return .none

        // Phase 3 — Mac Context Lens read-only tools. The frontmost-app /
        // selection / clipboard-meta / OCR helpers are inspection-only;
        // the tool call itself is the user's explicit intent ("look at
        // my screen"). No modal needed.
        case "active_window", "selected_items", "current_context", "screen_ocr":
            return .none

        case "weather":
            return .none

        case "unit_convert":
            return .none

        case "ocr":
            return .none

        case "image_convert":
            return .modal

        case "youtube_search":
            return .none

        case "youtube_download":
            return .modal

        case "shell":
            return shellApproval(arguments)

        // MARK: Code Companion (Phase 6)
        case "project_context":
            // Read-only repo analysis — no side effects.
            return .none

        case "enable_dev_mode":
            // Relaxes write_file policy for the session — must be explicit.
            return .modal

        case "disable_dev_mode":
            // Restores policy to safe defaults — no user risk.
            return .none

        // MARK: Skill Capsules (Phase 7a)
        case "create_skill":
            // Saving a skill is session-policy state (same tier as enable_dev_mode).
            return .modal

        case "delete_skill":
            // Destructive: permanently removes a saved skill recipe.
            return .modal

        case "list_skills", "inspect_skill":
            // Read-only — no side effects.
            return .none

        case "run_skill":
            // The run_skill call itself needs no top-level approval.
            // Each individual step inside is gated by its own tool's ApprovalPolicy.
            return .none

        default:
            return .modal  // unknown tool = always ask
        }
    }

    private static func applyUserOverride(toolName: String, arguments: [String: Any], base: ApprovalLevel) -> ApprovalLevel {
        guard let setting = AppSettings.storedToolApprovalOverride(for: toolName) else {
            return base
        }

        let floor = safetyFloor(toolName: toolName, arguments: arguments)
        if floor == .forbidden || base == .forbidden {
            return .forbidden
        }

        switch setting {
        case .deny:
            return .forbidden
        case .ask:
            return .modal
        case .auto:
            return floor == .modal ? .modal : .none
        }
    }

    /// Non-negotiable safety checks that user overrides cannot bypass.
    private static func safetyFloor(toolName: String, arguments: [String: Any]) -> ApprovalLevel {
        switch toolName {
        case "read_file":
            return requiredPathApproval(arguments["path"] as? String ?? "")
        case "create_directory", "list_directory", "write_file":
            return requiredPathApproval(arguments["path"] as? String ?? "")
        case "move_file":
            return maxApproval(
                requiredPathApproval(arguments["source"] as? String ?? ""),
                requiredPathApproval(arguments["destination"] as? String ?? "")
            )
        case "git_status", "git_diff":
            return requiredPathApproval(arguments["repo_path"] as? String ?? "")
        case "search_files":
            return requiredPathApproval(arguments["path"] as? String ?? NSHomeDirectory())
        case "shell":
            let cmd = (arguments["command"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let lower = cmd.lowercased()
            let forbiddenPatterns = [
                "sudo ", "su ", "mkfs", "dd if=", "> /dev/",
                "rm -rf /", "chmod -r 777 /", "chmod 777 /"
            ]
            if forbiddenPatterns.contains(where: { lower.contains($0) }) {
                return .forbidden
            }
            let downloaders = ["curl ", "wget "]
            let shellSinks = ["| sh", "|sh", "| bash", "|bash", "| zsh", "|zsh"]
            if downloaders.contains(where: { lower.contains($0) })
                && (shellSinks.contains(where: { lower.contains($0) }) || containsDownloadThenExecuteChain(lower)) {
                return .forbidden
            }
            return extractPathApproval(from: cmd)
        case "applescript", "mail_check", "mail_triage", "phone_call":
            return .modal
        default:
            return .none
        }
    }

    private static func requiredPathApproval(_ path: String) -> ApprovalLevel {
        switch PathPolicy.check(path) {
        case .denied: return .forbidden
        case .requiresApproval: return .modal
        case .allowed: return .none
        }
    }

    private static func maxApproval(_ lhs: ApprovalLevel, _ rhs: ApprovalLevel) -> ApprovalLevel {
        if lhs == .forbidden || rhs == .forbidden { return .forbidden }
        if lhs == .modal || rhs == .modal { return .modal }
        return .none
    }

    // MARK: - Shell Command Analysis

    private static func shellApproval(_ arguments: [String: Any]) -> ApprovalLevel {
        let cmd = (arguments["command"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let lower = cmd.lowercased()

        // Forbidden — never allow. All patterns must be lowercase: they are
        // compared against `lower`, so capital letters here would never match.
        let forbiddenPatterns = [
            "sudo ", "su ", "mkfs", "dd if=", "> /dev/",
            "rm -rf /", "chmod -r 777 /", "chmod 777 /"
        ]
        if forbiddenPatterns.contains(where: { lower.contains($0) }) {
            return .forbidden
        }

        // Forbidden: download-and-execute chains, whether piped directly to a shell
        // or written to disk and executed later in the same command line.
        let downloaders = ["curl ", "wget "]
        let shellSinks = ["| sh", "|sh", "| bash", "|bash", "| zsh", "|zsh"]
        if downloaders.contains(where: { lower.contains($0) })
            && (shellSinks.contains(where: { lower.contains($0) }) || containsDownloadThenExecuteChain(lower)) {
            return .forbidden
        }

        // Modal — destructive or write operations
        let writePatterns = [
            "rm ", "rm -", "rmdir", "mv ", "cp ", "mkdir",
            "touch ", "chmod", "chown", "kill ", "killall", "pkill",
            "brew install", "brew uninstall", "pip install", "pip uninstall",
            "npm install", "launchctl", "defaults write", "defaults delete",
            "networksetup", "scutil", "pmset", "dscl", "hdiutil",
            "tee ", ">>", "> "
        ]
        if writePatterns.contains(where: { lower.contains($0) }) {
            return .modal
        }

        // Check path policy for any path-like arguments in the command.
        let pathApproval = extractPathApproval(from: cmd)
        if pathApproval != .none {
            return pathApproval
        }

        // None — read-only commands
        return .none
    }

    // MARK: - Path Helpers

    private static func pathToApproval(_ path: String, defaultForAllowed: ApprovalLevel) -> ApprovalLevel {
        switch PathPolicy.check(path) {
        case .denied: return .forbidden
        case .requiresApproval: return .modal
        case .allowed: return defaultForAllowed
        }
    }

    private static func structuredReadApproval(_ path: String) -> ApprovalLevel {
        guard let resolved = structuredPath(for: path) else { return .modal }
        return pathToApproval(resolved, defaultForAllowed: .none)
    }

    private static func structuredWriteApproval(_ path: String) -> ApprovalLevel {
        guard let resolved = structuredPath(for: path) else { return .modal }
        switch PathPolicy.check(resolved) {
        case .denied: return .forbidden
        case .requiresApproval, .allowed: return .modal
        }
    }

    private static func structuredMoveApproval(source: String, destination: String) -> ApprovalLevel {
        guard let sourceResolved = structuredPath(for: source),
              let destinationResolved = structuredPath(for: destination) else {
            return .modal
        }

        if case .denied = PathPolicy.check(sourceResolved) { return .forbidden }
        if case .denied = PathPolicy.check(destinationResolved) { return .forbidden }
        return .modal
    }

    private static func structuredPath(for path: String) -> String? {
        FileToolPaths.resolvedURL(for: path)?.path
    }

    /// Best-effort path extraction from shell commands. Quoted, relative, env-expanded,
    /// and subshell-based paths are treated conservatively instead of being ignored.
    private static func extractPathApproval(from command: String) -> ApprovalLevel {
        for token in shellTokens(from: command) {
            if let approval = approvalForShellToken(token) {
                if approval != .none {
                    return approval
                }
            }
        }
        return .none
    }

    private static func approvalForShellToken(_ token: String) -> ApprovalLevel? {
        let candidate = token.trimmingCharacters(in: pathTokenTrimCharacters)
        guard looksPathLike(candidate) else { return nil }

        if candidate.contains("$(") || candidate.contains("`") {
            return .modal
        }

        guard let canonicalPath = canonicalShellPath(from: candidate) else {
            return .modal
        }

        return pathToApproval(canonicalPath, defaultForAllowed: .none)
    }

    private static func looksPathLike(_ token: String) -> Bool {
        token.hasPrefix("/") ||
        token.hasPrefix(".") ||
        token.hasPrefix("~") ||
        token.hasPrefix("$") ||
        token.contains("/")
    }

    private static func canonicalShellPath(from token: String) -> String? {
        let expandedTilde = NSString(string: expandEnvironmentVariables(in: token)).expandingTildeInPath
        guard !expandedTilde.contains("$("), !expandedTilde.contains("`") else {
            return nil
        }

        let url: URL
        if expandedTilde.hasPrefix("/") {
            url = URL(fileURLWithPath: expandedTilde)
        } else {
            url = URL(fileURLWithPath: expandedTilde, relativeTo: URL(fileURLWithPath: NSHomeDirectory()))
        }

        return url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func expandEnvironmentVariables(in string: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\$(\{)?([A-Za-z_][A-Za-z0-9_]*)\}?"#) else {
            return string
        }

        let range = NSRange(string.startIndex..., in: string)
        let matches = regex.matches(in: string, range: range)
        guard !matches.isEmpty else { return string }

        var result = ""
        var cursor = string.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: string) else { continue }
            result += String(string[cursor..<matchRange.lowerBound])

            if let nameRange = Range(match.range(at: 2), in: string) {
                let name = String(string[nameRange])
                if let value = ProcessInfo.processInfo.environment[name] {
                    result += value
                } else {
                    result += String(string[matchRange])
                }
            } else {
                result += String(string[matchRange])
            }

            cursor = matchRange.upperBound
        }

        result += String(string[cursor...])
        return result
    }

    private static func shellTokens(from command: String) -> [String] {
        var tokens: [String] = []
        var token = ""
        var quote: Character?
        var escaping = false

        for character in command {
            if escaping {
                token.append(character)
                escaping = false
                continue
            }

            if character == "\\" {
                escaping = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    token.append(character)
                }
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
                continue
            }

            if character.isWhitespace {
                if !token.isEmpty {
                    tokens.append(token)
                    token = ""
                }
                continue
            }

            token.append(character)
        }

        if !token.isEmpty {
            tokens.append(token)
        }

        return tokens
    }

    private static let pathTokenTrimCharacters = CharacterSet(charactersIn: "()[]{}<>.,;|&")

    private static func containsDownloadThenExecuteChain(_ command: String) -> Bool {
        let pattern = #"(?:curl|wget)\b[\s\S]*?(?:&&|\|\||;)\s*(?:sh|bash|zsh)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(command.startIndex..., in: command)
        return regex.firstMatch(in: command, range: range) != nil
    }
}
