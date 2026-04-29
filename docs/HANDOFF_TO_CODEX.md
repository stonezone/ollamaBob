# Hand-off to next agent (Codex / Claude / whoever)

**Source session:** Claude Opus, 2026-04-28.
**State of `main`:** version `1.0.22` / build `122`. **253 tests, 0 failures.** Clean working tree.
**Plan source of truth:** `docs/PEER_REVIEW_TODO.md`. **Findings:** `docs/PEER_REVIEW.md`. **Phase 5 sub-plan:** `docs/PHASE_5_PLAN.md` (BLOCKED — see §Owner answers below).

---

## What landed in this session (8 phases on `main`, all `--no-ff` merged)

| Phase | Tag | Test count | Version | What |
|---|---|---|---|---|
| 0b | `phase-0b-complete-20260428` | 132 → 153 | 1.0.15 | SwiftSoup pre-WebView allowlist sanitizer; CSP/JS-disabled/nav-block retained as defense-in-depth layers 2–4. |
| 0c | `phase-0c-complete-20260428` | 153 → 172 | 1.0.16 | macOS Keychain wrapper + one-time-prompt UserDefaults migration; `KeychainService.testOverride` + `JarvisDefaultsScope` install `InMemorySecretStore` so production secrets cannot leak via test failure messages. |
| 2a | `phase-2a-complete-20260428` | 172 (no Δ) | 1.0.17 | AgentLoop 1879 → 355 LOC across 8 coordinator extensions. Behavior-preserving refactor. BobsDeskView decomposition deferred to Phase 8 per Owner Option C. |
| 1a | `phase-1a-complete-20260428` | 172 → 180 | 1.0.18 | Diff Guardian: `write_file` approval modal shows unified diff via in-band sentinel; `ApprovalHandler` typealias unchanged. |
| 1b | `phase-1b-complete-20260428` | 180 → 189 | 1.0.19 | Execution log GRDB table + Privacy Ledger view (Preferences "Privacy" tab); side-effecting tools logged, read-only NEVER logged. |
| 3 | `phase-3-complete-20260428` | 189 → 210 | 1.0.20 | Mac Context Lens: `active_window`, `selected_items`, `screen_ocr`, `current_context` tools. ScreenCaptureKit + Vision. NSScreenCaptureUsageDescription added. `ContextChipView` standalone, ready to drop in. **Unanimous 4/4 peer #1 pick.** |
| 4a | `phase-4a-complete-20260428` | 210 → 224 | 1.0.21 | Jarvis Call Cockpit (mock + UI): `phone_list_calls`, `phone_get_transcript`, `phone_inject` tools + `LiveCallView` window. `JarvisCallClientMock` is `#if DEBUG`-gated; release builds always use `JarvisCallClientHTTP` stub that throws `.notImplemented`. **Phase 4b** swaps in real HTTP (blocked on Jarvis daemon endpoints — see below). |
| 6 | `phase-6-complete-20260428` | 224 → 253 | 1.0.22 | Code Companion: `project_context`, `enable_dev_mode`, `disable_dev_mode` tools + `DevModeStore`. write_file inside detected `.git` root auto-approves; shell NEVER auto-approves; path-prefix attack defended. |
| 0a | n/a (extraction-only) | n/a | n/a | Stash `peer-review security correctness pass` extracted to `.local-docs/STASH_REFERENCE_BACKLOG.md` (gitignored, 17 REF items). Stash retained until after Phase 2a per owner directive. |

**Recovery anchors retained:** `pre-phase-{0b,0c,1a,1b,2a,3,4a,6}-20260428` for one-command revert.

---

## What's next on the plan

### Phase 7 — Polish layer (sequential within phase, owner-stated order in `PEER_REVIEW_TODO.md` §4)

**7a. V4 Skill Capsules.** GRDB `skill` table + declarative recipes over existing tools only. `create_skill`, `list_skills`, `inspect_skill`, `run_skill` tools. **Hard rule:** a skill is a recipe, NOT an executable scripting layer; ApprovalPolicy applies per-step.

**7b. V5 Walkie-Talkie.** `Services/SpeechService.swift` using `SFSpeechRecognizer` + `AVSpeechSynthesizer` + global hotkey via `NSEvent.addGlobalMonitor`. Push-to-talk only.

**7c. N2 Focus Guardian.** `Services/FocusService.swift` observing `NSWorkspace.shared.runningApplications`; map bundle-id → context profile → optional persona swap (with manual override always visible). Subtle indicator in desk view (defer integration to Phase 8 like ContextChipView/DevModeIndicator).

**7d. V8 Clipboard Cortex.** Passive `NSPasteboard` watcher with cheap regex-gated trigger before model invocation; results as a chip in the menu-bar dropdown, not auto-pasted.

**7e. V7 Proactive / Daily Briefing.** `BackgroundTasks` + `SchedulerService` persisting cron-like expressions in `AppSettings`. Read-only auto-approval in headless mode only.

Each sub-phase: own feature branch + tag pair (`pre-phase-7X-{YYYYMMDD}` / `phase-7X-complete-{YYYYMMDD}`). One Sonnet sub-agent dispatch each. ~200–400 LOC each. The pattern from this session works well — see "Sub-agent dispatch recipe" below.

### Phase 4b — Real Jarvis daemon integration

**Blocked on**: owner confirmation that the Jarvis daemon at `http://127.0.0.1:3100` exposes (or will expose) `/call/list`, `/call/transcript`, `/call/inject` with the existing dual-secret auth contract (`X-Jarvis-Key` + `x-operator-secret`).

When unblocked: implement `JarvisCallClientHTTP` (currently a stub throwing `.notImplemented`); flip `AppSettings.useMockedJarvisClient` default to `false` in DEBUG too; add a Preferences toggle exposing the override; smoke-test against a running daemon. Do NOT change the dual-secret auth contract.

### Phase 5 — Local Knowledge Layer

**Blocked on 4 owner answers** (see `docs/PHASE_5_PLAN.md`):
1. Sub-phase order: A (timeline-first, recommended) or B (vault-first)?
2. Embedding model: Apple `NLContextualEmbedding` (no deps) or bundled CoreML MiniLM (better, larger)?
3. Default folders: confirm always opt-in?
4. PDF chunking: in v1 or out?

Once those four are answered, Phase 5 splits into 6 sub-phases (5.1–5.6) each ≤ 600 LOC.

### Phase 8 — Deferred BobsDeskView decomposition

Three Phase-3/6/7 standalone views are waiting to be wired into the desk surface:
- `Views/ContextChipView.swift` (Phase 3) — observes `MacContextStore.shared.lastContext`.
- `Views/DevModeIndicator.swift` (Phase 6) — observes `DevModeStore.shared.repoRoot`.
- `Views/LiveCallView.swift` (Phase 4a) — already gets a dedicated window, but a small inline live-call indicator might also belong on the desk.

Phase 8 decomposes BobsDeskView into 4–5 subviews plus view-models, then drops these chips in. Plan target end-state: BobsDeskView ≤ 800 LOC. See `docs/PEER_REVIEW_TODO.md` §4 Phase 2 — the 2b body was deferred and needs to be re-scoped here as Phase 8.

---

## How sub-agents were dispatched (use this recipe)

Three rules made the Sonnet sub-agents reliable:

1. **Tight scope box.** Explicit "files you MAY modify" + "files you MAY NOT touch" lists. The "may not" list ALWAYS includes `AgentLoop.swift`, `BobsDeskView.swift`, `PreferencesView.swift` unless that phase explicitly authorizes a small delta on one of them.

2. **Compliance check-in (§6.5 of `PEER_REVIEW_TODO.md`).** Sub-agent must restate the top STOPs + the primary forbidden file + the first scope-IN bullet they'll start with, BEFORE writing any code. If they get it wrong, terminate and re-dispatch. (Did not need to re-dispatch this session.)

3. **No commits from the sub-agent.** Supervisor (you) does the bundled commit + `--no-ff` merge + tag + branch delete. Sub-agent returns an LOC delta report + test count + scope confirmation.

Per-phase sequence:
```bash
DATE=$(date +%Y%m%d)   # use 20260429 for tomorrow's runs
git tag pre-phase-{slug}-${DATE}
git switch -c feature/phase-{slug}-${DATE}
# (dispatch Sonnet sub-agent with the recipe in PEER_REVIEW_TODO.md §6)
# (verify build + tests + LOC discipline + scope confirmation)
git add -A
git -c commit.gpgsign=false commit -m "..."
git switch main
git merge --no-ff feature/phase-{slug}-${DATE} -m "..."
git tag phase-{slug}-complete-${DATE}
git branch -d feature/phase-{slug}-${DATE}
```

**Sub-agent timeout note**: Sonnet usually finishes 200–400 LOC phases in 5–10 min. The longest dispatch this session was Phase 6 at ~13 min. If a Sonnet dispatch takes > 20 min, suspect a stuck loop and check the working tree directly.

---

## Things that need attention but didn't block the plan

1. **Phase 0c known leak.** A real `OPERATOR_API_SECRET` (`ff32...91a8`) leaked from the developer's Keychain into Phase 0c test failure stdout during development before the test seam was added. Owner said don't worry about it; the seam (`KeychainService.testOverride`) is now in place so this CANNOT happen again. Owner can rotate at their leisure.

2. **`STASH_REFERENCE_BACKLOG.md` REF items not consumed.** Phase 1 was scoped to V6 trust UI, not the broader stash backlog. Items REF-1 (TOCTOU `approvedResolvedPath` for FileWriteTool), REF-3 (FileMoveTool source/dest path-policy double-check), REF-4 (forbidden-path-beats-write precedence in shell parsing), REF-5 (tokenized shell parsing), REF-11/12/13 (ProcessRunner output caps + detached task) are all worth landing. They are referenced as natural Phase 1+ follow-ups but were left for a future cleanup pass. Owner explicitly authorized REF items to be landed in any phase that touches the same surface, but I did not piggyback to keep phase scopes clean.

3. **`OPERATOR_QA.md` is stale.** Last updated 2026-04-27 / 1.0.14. Eight phases of new features have shipped since. A Phase 9-style QA doc refresh would be cheap and high-value before any further user-facing work.

4. **`docs/CURRENT_HANDOFF.md` is also stale.** Same — written for 1.0.14. The version refs were bumped per phase, but the body still describes 1.0.14 capabilities. A refresh after Phase 7 would be appropriate.

5. **`MultimediaBobTests.swift`'s old `testPresentationServiceSanitizerStripsEventHandlersAndJavascriptURLs` test still exists alongside the 21 new `PresentationSanitizerTests` from Phase 0b.** Both pass; not a problem, just dup coverage. Could be cleaned up.

6. **Single SourceKit-noise pattern observed every dispatch.** SourceKit (the editor's incremental indexer) consistently lags behind newly-created Swift files, producing "Cannot find type X in scope" diagnostics that resolve as soon as `swift build` runs. This is a known Swift tooling quirk; don't be alarmed by these reports during a sub-agent dispatch.

---

## Owner decisions outstanding (in priority order)

1. **Push to remote?** Local main is 18 commits ahead of `origin/main`. The session never executed `git push` because the plan's branch protocol (§1.5) didn't authorize it without owner consent. Once owner authorizes, a single `git push origin main && git push origin --tags` ships everything.

2. **Phase 5 (`docs/PHASE_5_PLAN.md`) — answer the 4 questions** to unblock Local Knowledge Layer work.

3. **Phase 4b — confirm Jarvis daemon endpoint inventory** (`/call/list`, `/call/transcript`, `/call/inject`) and dual-secret auth.

4. **Phase 7 ordering** — start with 7a Skill Capsules (highest leverage) or 7e Daily Briefing (most "alive feeling")?

5. **STASH_REFERENCE_BACKLOG REF items** — land as a single Phase 1.5 cleanup commit, or piggyback into the next phase that touches the same files?

---

## Codex hand-off pointers

- `docs/PEER_REVIEW.md` — full multi-peer review synthesis (4-of-5 peers; 4/4 unanimous on V1/V2/V3).
- `docs/PEER_REVIEW_TODO.md` — phased plan with 16 STOP triggers, branch/tag protocol, compliance check-in pattern.
- `docs/PHASE_5_PLAN.md` — re-scoped Phase 5 (blocked on owner answers).
- `.local-docs/STASH_REFERENCE_BACKLOG.md` — 17 REF items extracted from a parked security/correctness stash (gitignored).
- This file — what's done, what's next, the dispatch recipe.

The supervision pattern in `PEER_REVIEW_TODO.md` §0–§7 is generic enough that any next agent can pick up at Phase 4b / 5.x / 7a without rebuilding context. Compliance Check-in is the single most important discipline — don't skip it.
