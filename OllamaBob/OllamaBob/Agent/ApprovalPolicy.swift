import Foundation

enum ApprovalPolicy {
    /// Determine the approval level for a tool call.
    static func check(toolName: String, arguments: [String: Any]) -> ApprovalLevel {
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

        case "web_search":
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

        case "shell":
            return shellApproval(arguments)

        default:
            return .modal  // unknown tool = always ask
        }
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
