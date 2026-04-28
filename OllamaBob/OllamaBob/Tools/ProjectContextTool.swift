import Foundation

/// Code Companion Mode — project_context tool (Phase 6).
///
/// Walks up from a given path to find the nearest `.git` root, identifies the
/// project language from manifest files, reads the dominant manifest head,
/// and returns recent git log + diff --stat output — all read-only.
///
/// Output is wrapped in `<untrusted>` because it contains file contents and
/// git history that must be treated as DATA, not instructions.
enum ProjectContextTool {

    // MARK: - Manifest detection

    private struct ManifestInfo {
        let language: String
        let fileName: String
    }

    private static let manifestPriority: [ManifestInfo] = [
        ManifestInfo(language: "Swift",      fileName: "Package.swift"),
        ManifestInfo(language: "Rust",       fileName: "Cargo.toml"),
        ManifestInfo(language: "Go",         fileName: "go.mod"),
        ManifestInfo(language: "JavaScript", fileName: "package.json"),
        ManifestInfo(language: "Python",     fileName: "pyproject.toml"),
        ManifestInfo(language: "Ruby",       fileName: "Gemfile"),
        ManifestInfo(language: "Java",       fileName: "pom.xml"),
    ]

    // MARK: - Public entry point

    static func execute(path: String) async -> ToolResult {
        let start = Date()

        // Resolve the starting path.
        guard let startURL = FileToolPaths.resolvedURL(for: path) else {
            return .failure(
                tool: "project_context",
                error: "Invalid path: \(path)",
                durationMs: 0
            )
        }

        // Walk up to find .git root.
        guard let repoRoot = findGitRoot(from: startURL) else {
            let durationMs = elapsed(since: start)
            return .failure(
                tool: "project_context",
                error: "No .git repository found above \(startURL.path). "
                     + "Make sure the path is inside a git repository.",
                durationMs: durationMs
            )
        }

        // Identify language(s) from manifest files present at the repo root.
        let (languages, dominantManifest) = detectLanguage(at: repoRoot)
        let langString = languages.isEmpty ? "Unknown" : languages.joined(separator: "+")

        // Read first 80 lines of the dominant manifest file.
        let manifestHead = dominantManifest.flatMap { readManifestHead(at: repoRoot, fileName: $0) } ?? ""

        // Run git log and git diff --stat.
        let gitLog = await runGit(args: ["log", "-10", "--oneline"], repoURL: repoRoot, timeout: 5)
        let gitDiff = await runGit(args: ["diff", "--stat", "HEAD"], repoURL: repoRoot, timeout: 5)

        let durationMs = elapsed(since: start)

        // Compose output — bounded at 8KB.
        var parts: [String] = []
        parts.append("Repo root: \(repoRoot.path)")
        parts.append("Language: \(langString)")
        if !manifestHead.isEmpty {
            parts.append("\nManifest (\(dominantManifest ?? "")):\n\(manifestHead)")
        }
        if !gitLog.isEmpty {
            parts.append("\nRecent commits (git log -10 --oneline):\n\(gitLog)")
        }
        if !gitDiff.isEmpty {
            parts.append("\nWorking tree changes (git diff --stat HEAD):\n\(gitDiff)")
        }

        let combined = parts.joined(separator: "\n")
        let bounded = String(combined.prefix(8 * 1024))
        let wrapped = UntrustedWrapper.wrap(bounded)

        return .success(tool: "project_context", content: wrapped, durationMs: durationMs)
    }

    // MARK: - .git root walk

    /// Walks up from `start`, looking for a `.git` directory or file.
    /// Bounded at 32 ancestors to avoid runaway traversal on pathological mounts.
    static func findGitRoot(from start: URL) -> URL? {
        var current = start.standardizedFileURL
        // If start is a file, begin with its parent directory.
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: current.path, isDirectory: &isDir)
        if !isDir.boolValue {
            current = current.deletingLastPathComponent()
        }

        for _ in 0..<32 {
            let gitPath = current.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitPath.path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            // Reached filesystem root — stop.
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    // MARK: - Language detection

    private static func detectLanguage(at repoRoot: URL) -> (languages: [String], dominant: String?) {
        var found: [ManifestInfo] = []
        for manifest in manifestPriority {
            let url = repoRoot.appendingPathComponent(manifest.fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                found.append(manifest)
            }
        }
        // Additionally probe for .xcodeproj directories (Swift/ObjC).
        if !found.contains(where: { $0.language == "Swift" }) {
            let xcodeproj = findXcodeproj(in: repoRoot)
            if xcodeproj != nil {
                found.insert(ManifestInfo(language: "Swift", fileName: xcodeproj!), at: 0)
            }
        }
        let languages = found.map(\.language)
        let dominant = found.first?.fileName
        return (languages, dominant)
    }

    private static func findXcodeproj(in repoRoot: URL) -> String? {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: repoRoot.path) else {
            return nil
        }
        return items.first(where: { $0.hasSuffix(".xcodeproj") })
    }

    // MARK: - Manifest head

    private static func readManifestHead(at repoRoot: URL, fileName: String) -> String? {
        let url = repoRoot.appendingPathComponent(fileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\n")
        let head = lines.prefix(80).joined(separator: "\n")
        return head.isEmpty ? nil : head
    }

    // MARK: - Git subprocess

    private static func runGit(args: [String], repoURL: URL, timeout: TimeInterval) async -> String {
        let result = await ProcessRunner.run(
            executable: "/usr/bin/git",
            arguments: ["-C", repoURL.path] + args,
            timeout: timeout
        )
        if result.timedOut { return "(git timed out)" }
        if result.exitCode != 0 {
            let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return err.isEmpty ? "(exit \(result.exitCode))" : err
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers

    private static func elapsed(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}
