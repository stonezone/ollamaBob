import Foundation

/// Declarative catalog of every external CLI tool Bob knows about.
/// Loaded from `Resources/ToolCatalog.json` at startup via Bundle.module.
///
/// This file defines the *schema only* — it does NOT decide whether a tool
/// is actually usable in the current session. That's `ToolRuntime`'s job:
/// it probes each non-bundled entry via `which` at launch, runs a
/// `--version` smoke test, and marks it live / missing / broken.
///
/// Keep fields flat and simple: the cheat-sheet renderer (Phase 3.2) reads
/// the catalog directly, and gemma4:e4b chokes on nested schemas.
struct ToolCatalogEntry: Codable, Hashable, Identifiable {
    /// Command name as it would be typed in a shell (also used as the
    /// lookup key for `which` probes and `tool_help(name)`).
    let name: String

    /// Grouping for the Preferences UI and the cheat sheet: "data",
    /// "search", "files", "security", "pdf", "ocr", "docs", "media",
    /// "metadata", "qr", "ctf". Not an enum on purpose — the catalog
    /// is the source of truth and new categories shouldn't require a
    /// code change.
    let category: String

    /// 1 = always in the cheat sheet, 2 = hidden unless the tier-1 set
    /// fits under the 800-token budget (see Phase 3.2 in V2 plan).
    let tier: Int

    /// Gated behind Preferences → Tools → Beta. Two reasons tools end
    /// up here: (a) complex shell quoting that stresses gemma4:e4b,
    /// (b) CTF/security tools that need an explicit opt-in.
    let beta: Bool

    /// True if the tool ships inside the .app bundle (jq/yq/rg/fd/…).
    /// Bundled tools are always present; non-bundled are Homebrew-detected
    /// at launch.
    let bundled: Bool

    /// One-line summary for the cheat sheet (≈ 8 words). Rendered as
    /// `name — shortDescription` per line.
    let shortDescription: String

    /// When should Bob reach for this tool? Surfaced by `tool_help(name)`
    /// so the model can double-check its own choice. Plain English, one
    /// sentence.
    let whenToUse: String

    /// A concrete, copy-pasteable example command. Keep it under ~80
    /// chars so it renders cleanly in the activity log.
    let example: String

    /// Shortlist of the most-used flags with a short gloss each.
    /// Rendered inline when `tool_help(name)` is called.
    let commonFlags: [String]

    /// Optional discriminator for name-collision cases. When set, the
    /// probe requires the tool's `--version` output to contain this
    /// case-insensitive substring before marking the tool as live.
    /// Example: `httpx` collides between ProjectDiscovery's Go CTF tool
    /// and Python's HTTPX library — we set this to "projectdiscovery"
    /// so a shim pointing at the Python package is correctly rejected.
    /// Nil means "accept anything that runs `--version` cleanly."
    let versionMatch: String?

    /// Override for the version-check command. Some tools reject `--version`
    /// (poppler's pdftotext wants `-v`, exiftool wants `-ver`, ffuf wants
    /// `-V`, ffmpeg wants `-version`). When set, ToolRuntime uses this
    /// flag instead of `--version`. Nil means use the default `--version`.
    let versionFlag: String?

    var id: String { name }
}

/// Top-level wrapper for the JSON file. `version` lets us evolve the
/// schema later without silently breaking older installs.
struct ToolCatalog: Codable {
    let version: Int
    let tools: [ToolCatalogEntry]
}

extension ToolCatalog {
    /// Load and decode the catalog from the SPM-processed resource bundle.
    /// Throws on missing file or malformed JSON — both are startup bugs
    /// we want to fail loudly on in debug, not limp along with a stub.
    static func loadFromBundle() throws -> ToolCatalog {
        guard let url = Bundle.module.url(forResource: "ToolCatalog", withExtension: "json") else {
            throw ToolCatalogError.resourceMissing
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ToolCatalog.self, from: data)
    }
}

enum ToolCatalogError: Error, LocalizedError {
    case resourceMissing

    var errorDescription: String? {
        switch self {
        case .resourceMissing:
            return "ToolCatalog.json not found in Bundle.module — check Package.swift resources."
        }
    }
}
