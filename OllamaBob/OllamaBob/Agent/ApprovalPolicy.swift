import Foundation

enum ApprovalPolicy {
    /// Determine the approval level for a tool call.
    static func check(toolName: String, arguments: [String: Any]) -> ApprovalLevel {
        switch toolName {
        case "read_file":
            let path = arguments["path"] as? String ?? ""
            return pathToApproval(path, defaultForAllowed: .none)

        case "search_files":
            let path = arguments["path"] as? String ?? NSHomeDirectory()
            return pathToApproval(path, defaultForAllowed: .none)

        case "web_search":
            return .none

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

        // Forbidden: downloading and piping to a shell. Match any form of
        // `curl|wget ... | sh|bash|zsh` — the literal-substring checks above
        // only caught the pipe-with-no-URL form.
        let downloaders = ["curl ", "wget "]
        let shellSinks = ["| sh", "|sh", "| bash", "|bash", "| zsh", "|zsh"]
        if downloaders.contains(where: { lower.contains($0) })
            && shellSinks.contains(where: { lower.contains($0) }) {
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

        // Check path policy for any paths in the command
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

    /// Best-effort path extraction from shell commands
    private static func extractPathApproval(from command: String) -> ApprovalLevel {
        let tokens = command.split(separator: " ").map(String.init)
        for token in tokens {
            let expanded = NSString(string: token).expandingTildeInPath
            if expanded.hasPrefix("/") {
                let access = PathPolicy.check(expanded)
                if access == .denied { return .forbidden }
                if access == .requiresApproval { return .modal }
            }
        }
        return .none
    }
}
