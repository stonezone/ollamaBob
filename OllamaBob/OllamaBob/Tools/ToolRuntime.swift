import Foundation

/// Live state of a single catalog entry in the current session.
///
/// This is derived once at app launch by probing the catalog via `which`.
/// It is the source of truth for "can Bob actually call this tool right
/// now?" — the cheat sheet (Phase 3), the Preferences Tools tab, and
/// `tool_help` all read from here.
enum ToolState: Equatable {
    /// Ships inside the .app bundle (jq / yq / rg / fd / …). Always
    /// available. Phase 7 distribution hasn't landed actual bundled
    /// binaries yet, so today we always report `.missing` for bundled
    /// entries until Phase 7 adds a real on-disk probe.
    case bundled(version: String?)

    /// Found on $PATH (typically /opt/homebrew/bin) with a working
    /// `--version` smoke test. The version string is cached for the
    /// Preferences UI.
    case homebrewDetected(path: String, version: String?)

    /// Not on $PATH, or the `--version` smoke test failed. Cheat
    /// sheet hides these; Preferences shows them greyed out.
    case missing(reason: String)
}

/// @MainActor ObservableObject singleton that owns the per-session view of
/// `ToolCatalog` → `ToolState`. Loads the catalog once at init, then
/// probes every non-bundled entry in a background Task so app launch
/// stays snappy.
///
/// Not wired into AgentLoop yet. This is Phase 2.1 foundation — the
/// cheat-sheet renderer (Phase 3.2) and the self-test harness (Phase 2.4)
/// will read from here.
@MainActor
final class ToolRuntime: ObservableObject {
    static let shared = ToolRuntime()
    nonisolated private static let skipProbeEnvironmentKey = "OLLAMABOB_SKIP_PROBE"

    @Published private(set) var catalog: ToolCatalog
    @Published private(set) var states: [String: ToolState] = [:]
    @Published private(set) var isProbing: Bool = false

    private init() {
        do {
            self.catalog = try ToolCatalog.loadFromBundle()
        } catch {
            // Startup bug — log loudly and continue with an empty catalog.
            // A broken catalog should not block the rest of the app from
            // launching; Bob just won't have any detected tools this session.
            print("[ToolRuntime] Failed to load ToolCatalog.json: \(error.localizedDescription)")
            self.catalog = ToolCatalog(version: 0, tools: [])
        }

        // Pre-populate bundled entries so the UI has something to show
        // before the async probe finishes. Phase 7 will do a real on-disk
        // presence check here; for now every `bundled: true` entry shows
        // as missing because nothing is actually shipping in Contents/MacOS.
        for entry in catalog.tools where entry.bundled {
            states[entry.name] = .missing(reason: "Bundled binaries not shipped yet (Phase 7).")
        }
        for entry in catalog.tools where !entry.bundled {
            states[entry.name] = .missing(reason: "Not yet probed.")
        }

        guard Self.shouldAutoProbe else { return }
        Task { await self.probeAll() }
    }

    // MARK: - Probing

    /// Kick off a fresh probe of every non-bundled catalog entry. Safe to
    /// call multiple times — each run fully replaces the previous state
    /// for the tools it inspects. Runs the `which` checks concurrently.
    func probeAll() async {
        isProbing = true
        defer { isProbing = false }

        let entries = catalog.tools.filter { !$0.bundled }

        // Keep startup probes sequential for now. `ProcessRunner.run()` still
        // blocks a worker thread internally, so spawning one task per catalog
        // entry can starve the cooperative executor and hang the full test
        // suite. If we want parallel probing again, it should come back with a
        // truly async process runner or an explicit bounded queue.
        var results: [(String, ToolState)] = []
        results.reserveCapacity(entries.count)
        for entry in entries {
            results.append(await Self.probe(entry: entry))
        }

        for (name, state) in results {
            states[name] = state
        }
        logProbeSummary()
    }

    /// Print a startup summary to Console.app so the user can see what
    /// Bob detected without opening Preferences. Also useful for debugging.
    private func logProbeSummary() {
        let live = catalog.tools.filter {
            if case .homebrewDetected = states[$0.name] { return true }
            return false
        }
        let missing = catalog.tools.filter {
            if case .missing = states[$0.name] { return true }
            return false
        }
        let bundledPending = catalog.tools.filter { $0.bundled }

        var lines: [String] = ["[ToolRuntime] Probe complete:"]
        if !live.isEmpty {
            let liveNames = live.map { name in
                if case .homebrewDetected(_, let v) = states[name.name] {
                    return v != nil ? "\(name.name) (\(v!))" : name.name
                }
                return name.name
            }
            lines.append("  LIVE (\(live.count)): \(liveNames.joined(separator: ", "))")
        }
        if !missing.isEmpty {
            lines.append("  MISSING (\(missing.count)): \(missing.map(\.name).joined(separator: ", "))")
        }
        if !bundledPending.isEmpty {
            lines.append("  BUNDLED-PENDING (\(bundledPending.count)): \(bundledPending.map(\.name).joined(separator: ", "))")
        }
        for line in lines { print(line) }
    }

    /// Probe a single entry: run `which <name>` to find it on $PATH, then
    /// run `<name> --version` as a smoke test. Some tools don't respond
    /// to `--version` (they use `-V`, `-v`, or nothing) so a non-zero
    /// exit still counts as "detected" if `which` succeeded — we record
    /// the version as nil and move on. Self-test (Phase 2.4) will tighten
    /// this with per-tool expected-output checks.
    ///
    /// If the catalog entry has `versionMatch` set, the version output
    /// MUST contain that substring (case-insensitive) or we reject the
    /// detection — this is how we disambiguate name collisions like
    /// ProjectDiscovery httpx vs. Python httpx.
    private static func probe(entry: ToolCatalogEntry) async -> (String, ToolState) {
        guard let path = await runWhich(entry.name) else {
            return (entry.name, .missing(reason: "Not found on $PATH."))
        }
        let flag = entry.versionFlag ?? "--version"
        let version = await runVersion(path: path, flag: flag)
        if let expected = entry.versionMatch {
            guard let v = version,
                  v.range(of: expected, options: .caseInsensitive) != nil else {
                return (
                    entry.name,
                    .missing(reason: "Found at \(path) but \(flag) did not match '\(expected)'.")
                )
            }
        }
        return (entry.name, .homebrewDetected(path: path, version: version))
    }

    /// `which <name>` — returns the absolute path if found, nil otherwise.
    /// Runs via /bin/zsh -lc so Homebrew's /opt/homebrew/bin is on PATH
    /// even when launched from Finder (which doesn't source ~/.zshrc).
    private static func runWhich(_ name: String) async -> String? {
        let (stdout, exitCode) = await runProcess(
            executable: "/bin/zsh",
            arguments: ["-lc", "which \(name)"]
        )
        guard exitCode == 0 else { return nil }
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Run the tool with the given version flag and return the first
    /// line of stdout/stderr (whichever the tool writes to), truncated
    /// to 200 chars. nil if the tool exits non-zero or produces no output.
    private static func runVersion(path: String, flag: String) async -> String? {
        let (stdout, exitCode) = await runProcess(
            executable: path,
            arguments: [flag]
        )
        guard exitCode == 0 else { return nil }
        let firstLine = stdout
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        guard let line = firstLine, !line.isEmpty else { return nil }
        return String(line.prefix(200))
    }

    /// Low-level process runner used only by the probe. Deliberately
    /// separate from ShellTool: this never goes through the approval
    /// policy, never logs to the activity log, and has a hard 3s
    /// timeout because `which` / `--version` should be instantaneous.
    private static func runProcess(executable: String, arguments: [String]) async -> (stdout: String, exitCode: Int32) {
        let result = await ProcessRunner.run(
            executable: executable,
            arguments: arguments,
            timeout: 3.0
        )
        let merged = result.stdout.isEmpty ? result.stderr : result.stdout
        return (merged, result.exitCode)
    }

    // MARK: - Convenience accessors

    /// True if the tool is present in any form (bundled OR detected)
    /// AND not gated behind a disabled beta toggle.
    func isLive(_ name: String) -> Bool {
        // Beta gate: if the catalog entry is flagged beta and the user
        // hasn't enabled beta tools, treat it as not live.
        if let entry = catalog.tools.first(where: { $0.name == name }),
           entry.beta,
           !AppSettings.shared.betaToolsEnabled {
            return false
        }
        switch states[name] {
        case .bundled, .homebrewDetected: return true
        case .missing, .none: return false
        }
    }

    /// All catalog entries whose state is live this session. Order
    /// mirrors the catalog file for deterministic rendering.
    var liveEntries: [ToolCatalogEntry] {
        catalog.tools.filter { isLive($0.name) }
    }

    /// Live entries filtered to a single category. Useful for the
    /// Preferences UI grouping.
    func liveEntries(category: String) -> [ToolCatalogEntry] {
        catalog.tools.filter { $0.category == category && isLive($0.name) }
    }

    // MARK: - tool_help rendering

    /// Render the `tool_help("list")` response: every live tool grouped
    /// by category, one line per tool. Includes both first-class built-in
    /// tools and external CLI tools that are actually live this session.
    /// Kept deliberately terse — this is what Bob reads when he's uncertain
    /// which tool to pick, not a user-facing doc page.
    func renderToolHelpList() -> String {
        let builtins = liveBuiltinEntries()
        let external = liveEntries
        guard !builtins.isEmpty || !external.isEmpty else {
            return "No tools are available in this session."
        }

        var lines: [String] = ["Tools available this session:"]
        if !builtins.isEmpty {
            lines.append("")
            lines.append("Built-in tools:")
            let grouped = Dictionary(grouping: builtins, by: { $0.category })
            for category in BuiltinToolsCatalog.categoryOrder where grouped[category]?.isEmpty == false {
                lines.append("[\(category)]")
                for entry in grouped[category, default: []] {
                    lines.append("  \(entry.name) — \(entry.description)")
                }
                lines.append("")
            }
        }

        if !external.isEmpty {
            let grouped = Dictionary(grouping: external, by: { $0.category })
            let orderedCategories = grouped.keys.sorted()
            lines.append("External CLI tools on PATH:")
            for cat in orderedCategories {
                lines.append("[\(cat)]")
                for entry in grouped[cat, default: []] {
                    let betaTag = entry.beta ? " (beta)" : ""
                    lines.append("  \(entry.name)\(betaTag) — \(entry.shortDescription)")
                }
                lines.append("")
            }
        }

        if lines.last == "" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    /// Render the `tool_help("<name>")` response: full catalog entry
    /// for a specific tool. Returns a short error string if the name
    /// is unknown OR if the tool isn't live in this session (so the
    /// model doesn't try to call something that will just 404).
    func renderToolHelp(name: String) -> String {
        if let builtin = BuiltinToolsCatalog.entries.first(where: { $0.name == name }) {
            let registry = ToolRegistry(braveKeyAvailable: !AppConfig.braveAPIKey.isEmpty)
            guard registry.has(builtin.name) else {
                return "Tool '\(name)' is built in but not usable in this session."
            }
            return [
                "\(builtin.name) — \(builtin.description)",
                "category: \(builtin.category), approval: \(builtin.posture.rawValue)"
            ].joined(separator: "\n")
        }

        guard let entry = catalog.tools.first(where: { $0.name == name }) else {
            return "No catalog entry for '\(name)'. Call tool_help with name='list' to see what's available."
        }
        guard isLive(entry.name) else {
            let reason: String = {
                if case .missing(let r) = states[entry.name] { return r }
                return "not live"
            }()
            return "Tool '\(name)' is in the catalog but not usable in this session (\(reason))."
        }
        var lines: [String] = [
            "\(entry.name) — \(entry.shortDescription)",
            "category: \(entry.category), tier: \(entry.tier)\(entry.beta ? ", beta" : "")",
            "",
            "when to use:",
            "  \(entry.whenToUse)",
            "",
            "example:",
            "  \(entry.example)"
        ]
        if !entry.commonFlags.isEmpty {
            lines.append("")
            lines.append("common flags:")
            for flag in entry.commonFlags {
                lines.append("  \(flag)")
            }
        }
        if case .homebrewDetected(let path, let version) = states[entry.name] {
            lines.append("")
            lines.append("detected at: \(path)")
            if let v = version {
                lines.append("version: \(v)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func liveBuiltinEntries() -> [BuiltinToolsCatalog.Entry] {
        let registry = ToolRegistry(braveKeyAvailable: !AppConfig.braveAPIKey.isEmpty)
        return BuiltinToolsCatalog.entries.filter { registry.has($0.name) }
    }

    private static var shouldAutoProbe: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return false }
        if env[skipProbeEnvironmentKey] == "1" { return false }
        return true
    }
}
