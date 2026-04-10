import Foundation

/// Assembles the full system prompt that gets injected at the top of every
/// Ollama turn. The order is intentional and matches the V2 plan:
///
///     [OperatingRules] + [Persona] + [UserProfile?] + [ToolCheatSheet?]
///
/// UserProfile (Phase 4) is still TODO — the composer accepts an optional
/// slot for it so the call site doesn't need to change when it lands.
@MainActor
enum PromptComposer {

    /// Rough token estimate: ~4 chars per token. Used for budget checks.
    /// Not precise but fine for an upper-bound soft cap — we're guarding
    /// against runaway growth, not shaving individual tokens.
    static func approxTokens(_ s: String) -> Int { s.count / 4 }

    /// Token budget for the rendered cheat sheet alone. V2 plan §3.2
    /// calls for ≤ 800 tokens. If the tier-1 set still exceeds this
    /// after degradation, we print a warning and live with it.
    private static let cheatSheetTokenBudget = 800

    /// Per-turn breakdown of the composed system prompt. Emitted by
    /// `composeWithBreakdown` and surfaced in the tool activity log by
    /// AgentLoop on every turn so prompt drift is visible.
    struct Breakdown {
        let operatingRulesChars: Int
        let personaChars: Int
        let cheatSheetChars: Int
        let totalChars: Int
        let approxTokens: Int
        let budgetTokens: Int
        let overBudget: Bool
        /// Non-nil when the composer had to degrade a segment (cheat
        /// sheet tier-1-only, persona trimmed, …). Empty string means
        /// no degradation happened.
        let degradationNote: String
    }

    /// Budget for the *entire* system stack given a context window.
    /// Plan §3.4: ≤ 2500 tokens at num_ctx = 16384, ≤ 5000 at 32768.
    /// At 8K we tighten further since history eats context faster.
    static func budgetTokens(forNumCtx numCtx: Int) -> Int {
        switch numCtx {
        case ..<12288:  return 1500
        case ..<20480:  return 2500
        case ..<28672:  return 3750
        default:        return 5000
        }
    }

    /// Build the combined system prompt for a single turn.
    ///
    /// Pass `includeCheatSheet: false` to skip cheat-sheet rendering
    /// entirely — useful for tests or for the first turn of a brand-new
    /// chat where ToolRuntime may still be probing.
    static func compose(persona: Persona, includeCheatSheet: Bool = true) -> String {
        composeWithBreakdown(persona: persona, includeCheatSheet: includeCheatSheet).prompt
    }

    /// Maximum number of facts injected per turn (V2 plan §4.3).
    private static let maxFacts = 40
    /// Maximum tokens the USER PROFILE block may consume (V2 plan §4.3).
    private static let userProfileTokenBudget = 1200

    /// Same as `compose` but also returns the per-segment char / token
    /// breakdown for activity-log visibility. Call site: AgentLoop.
    static func composeWithBreakdown(
        persona: Persona,
        includeCheatSheet: Bool = true
    ) -> (prompt: String, breakdown: Breakdown) {
        let operatingRules = BobOperatingRules.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let personaText = persona.systemPromptMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let cheatSheet = includeCheatSheet ? (renderCheatSheet() ?? "") : ""
        let userProfile = renderUserProfile() ?? ""

        let segments = [operatingRules, personaText, userProfile, cheatSheet].filter { !$0.isEmpty }
        let prompt = segments.joined(separator: "\n\n")

        let budget = budgetTokens(forNumCtx: AppSettings.shared.numCtx)
        let tokens = approxTokens(prompt)
        let breakdown = Breakdown(
            operatingRulesChars: operatingRules.count,
            personaChars: personaText.count,
            cheatSheetChars: cheatSheet.count,
            totalChars: prompt.count,
            approxTokens: tokens,
            budgetTokens: budget,
            overBudget: tokens > budget,
            degradationNote: ""
        )
        return (prompt, breakdown)
    }

    /// Render the USER PROFILE block from stored facts.
    ///
    /// Rules (V2 plan §4.3):
    /// - Fetch all facts where lastUsedAt > 30 days ago OR category = 'identity'
    /// - Hard cap: 40 facts or 1200 tokens, whichever first
    /// - Identity facts are exempt from LRU trimming
    /// - Touch lastUsedAt for the injected set so active facts stay warm
    static func renderUserProfile() -> String? {
        do {
            var facts = try DatabaseManager.shared.fetchActiveFacts()
            guard !facts.isEmpty else { return nil }

            // Enforce the 40-fact cap. Identity facts are exempt from
            // trimming: sort them first, then fill remaining slots with
            // non-identity facts by lastUsedAt recency.
            let identity = facts.filter { $0.category == "identity" }
            let other = facts.filter { $0.category != "identity" }
                .sorted { $0.lastUsedAt > $1.lastUsedAt }
            let remaining = max(0, maxFacts - identity.count)
            facts = identity + Array(other.prefix(remaining))

            // Build the block and trim to token budget.
            var lines: [String] = ["USER PROFILE (facts Bob knows about the user):"]
            var totalTokens = approxTokens(lines[0])
            var includedIds: [String] = []

            for fact in facts {
                let line = "- [\(fact.category)] \(fact.content)"
                let lineTokens = approxTokens(line)
                if totalTokens + lineTokens > userProfileTokenBudget {
                    break
                }
                lines.append(line)
                totalTokens += lineTokens
                includedIds.append(fact.id)
            }

            guard includedIds.count > 0 else { return nil }

            // Touch lastUsedAt so these facts stay warm for next time.
            try DatabaseManager.shared.touchFacts(ids: includedIds)

            return lines.joined(separator: "\n")
        } catch {
            // Facts are best-effort — don't block the turn if the DB hiccups.
            print("[PromptComposer] Failed to load facts: \(error.localizedDescription)")
            return nil
        }
    }

    /// Render the tool cheat sheet as a system-prompt fragment.
    ///
    /// Rules (V2 plan §3.2):
    /// - Only live tools in the current session are listed.
    /// - Format: one line per tool, `name — shortDescription`, grouped by category.
    /// - Tier-1 listed first. If the full set fits under the 800-token budget,
    ///   tier-2 is appended. Otherwise the sheet is tier-1-only with a footer
    ///   pointing at `tool_help("list")` for the rest.
    ///
    /// Returns `nil` if there are no live tools (avoids polluting the prompt
    /// with an empty section).
    static func renderCheatSheet() -> String? {
        let runtime = ToolRuntime.shared
        let live = runtime.liveEntries
        guard !live.isEmpty else { return nil }

        let tier1 = live.filter { $0.tier == 1 }
        let tier2 = live.filter { $0.tier == 2 }

        // Try the full set first.
        let full = Self.buildSheet(header: "EXTRA TOOLS AVAILABLE THIS SESSION (call via `shell`):", entries: tier1 + tier2, footer: nil)
        if approxTokens(full) <= cheatSheetTokenBudget {
            return full
        }

        // Over budget — degrade to tier-1 only with a pointer footer.
        let hiddenCount = tier2.count
        let footer = hiddenCount > 0
            ? "\(hiddenCount) more tool\(hiddenCount == 1 ? "" : "s") available — call tool_help('list') to see all."
            : nil
        return Self.buildSheet(
            header: "EXTRA TOOLS AVAILABLE THIS SESSION (tier-1 shown; call via `shell`):",
            entries: tier1,
            footer: footer
        )
    }

    private static func buildSheet(header: String, entries: [ToolCatalogEntry], footer: String?) -> String {
        var lines: [String] = [header, ""]
        let grouped = Dictionary(grouping: entries, by: { $0.category })
        for category in grouped.keys.sorted() {
            guard let items = grouped[category], !items.isEmpty else { continue }
            lines.append("[\(category)]")
            for entry in items {
                let betaTag = entry.beta ? " (beta)" : ""
                lines.append("  \(entry.name)\(betaTag) — \(entry.shortDescription)")
            }
            lines.append("")
        }
        if let footer {
            lines.append(footer)
        }
        lines.append("Call tool_help('<name>') for usage details before running an unfamiliar tool.")
        return lines.joined(separator: "\n")
    }
}
