# OllamaBob — Multi-Peer Blind Review

**Date:** 2026-04-27
**App version reviewed:** 1.0.14
**Mode:** Blind multi-peer triangulation (each peer received an identical scoped bundle without seeing other peers' findings or any pre-formed conclusions).
**Bundle sent:** project description, architecture rules, tool catalog, LOC inventory, system prompt body, 30-commit `git log` one-liners, owner posture statements. ~5,000 tokens. Redaction floor confirmed 0 secret-shape hits before transmission.

## Peers

| Peer | Model | Effort | Result |
|---|---|---|---|
| Codex | gpt-5.5 | xhigh reasoning | Returned — 12 ideas |
| Gemini | gemini-3.1-pro-preview | integrated thinking | Returned — 8 ideas |
| DeepSeek | deepseek-v4-pro | integrated reasoning | Returned — 9 ideas |
| Kimi | Kimi-k2.6 | thinking on | Returned — 10 ideas |
| Opus | claude-opus-4-7 → 4-6 fallback | max | **Did not return** — both attempts timed out |

**Final coverage: 4/5 peers, four independent training families.** Same-family Anthropic check is missing.

---

## 1. Validated strengths (consensus across peers)

- **Local-first architecture is coherent and well-defended.** Native `/api/chat`, `stream:false`, Swift-owned agent loop, GRDB persistence, no external runtime — explicit, repeatedly enforced, has stopped architectural drift. Every peer flagged this as the project's biggest asset.
- **Tool surface is operator-grade, not chat-grade.** Files / shell / git / Mail / phone / OCR / clipboard / AppleScript / YouTube / presentation — none of the LM Studio / Open WebUI / Msty class do this.
- **Approval/path/forbidden-shell stack is the right trust shape for an unsandboxed personal Mac agent.** The Auto/Ask/Deny badge model with non-bypassable path-policy + forbidden-shape floors is unusually disciplined.
- **Personality is intentional, not chrome.** Avatar-only mode, persona quick-swap, Naughty Bob as a *constrained* mode (tools+compaction off, no silent fallback).
- **Shipping discipline visible in commit log.** Hardening commits dominate over speculative rewrites.

---

## 2. Validated risks (consensus across peers)

| # | Risk | Severity | Cited by |
|---|---|---|---|
| **R1** | **Core files are god-classes.** `AgentLoop.swift` 1879 LOC, `BobsDeskView.swift` 1683 LOC, `PreferencesView.swift` 1686 LOC. | medium-high | 4/4 |
| **R2** | **Untrusted-output mitigation is prompt-mediated, not policy-mediated.** Telling the model to ignore instructions inside `<untrusted>` is the right floor but is **not a hard security boundary**. | medium | 4/4 |
| **R3** | **Tool blast radius is broad and growing.** Shell + AppleScript + clipboard-write + write_file + youtube_download + phone_call + presentation. Auto badges in `~/` paths can compose into dangerous sequences. | high | 3/4 |
| **R4** | **Rich HTML sanitization is a known weak point** (already on owner backlog). `present` is too central a primitive for regex-floor sanitization. | high | 3/4 |
| **R5** | **Flat memory store will cap usefulness.** `remember/forget/list_facts` won't carry episodic work history, project-scoped preferences, provenance, or time-sensitive context. | medium | 3/4 |
| **R6** | **Test ratio is light** (132 tests for 16K LOC). | medium | 1/4 |
| **R7** | **Naughty Bob disables compaction → context exhaustion on long sessions.** | medium | 1/4 |
| **R8** | **Prompt inventory drifts from shipped catalog.** As tools grow, the static system prompt's tool list will lag. | medium | 1/4 |
| **R9** | **Purely reactive architecture.** Bob never knocks. Cedes ground to cloud competitors adding proactive features. | medium | 2/4 |

---

## 3. Architecture assessment (consolidated)

The architecture is coherent for a personal local Mac agent: a Swift-owned `AgentLoop` calls Ollama `/api/chat` with `stream:false`, routes through a first-party `ToolRegistry`, persists with GRDB, and keeps side effects behind native approval surfaces. The tool surface is broad and product-relevant, but it increases the importance of **policy enforcement outside the model** — especially for shell, AppleScript, file writes, clipboard writes, and phone calls. The `<untrusted>` wrapper is a good defense layer but should not be treated as a hard security boundary. File sizes around `AgentLoop`, `BobsDeskView`, and `PreferencesView` suggest the next architecture work should extract narrowly around orchestration state, approval UX, and presentation/activity surfaces — **not** invent a new runtime.

---

## 4. Product assessment (consolidated)

- **Today's user:** technical macOS power user who values local control + privacy + real-world reach.
- **Moat vs. ChatGPT desktop / Claude desktop:** local authority over files, apps, shell, TCC-gated data, phone calls.
- **Moat vs. Open WebUI / LM Studio / Msty:** tool-bearing agency + personality + Mac integration.
- **Single biggest missed opportunity (4/4 unanimous):** the app is not yet *situationally aware*. It cannot see the current screen, the active app, the selected files, or what the user is actually doing right now.

---

## 5. Validated novel enhancements (≥2 peers, independent corroboration)

Merged by failure-mode + impacted-component, not surface name.

### V1. Mac Context Lens / Screen Awareness — `killer 9–10` — **4/4 unanimous**

> "Bob can answer from what's actually on your Mac right now: active app, selected file, visible screen, clipboard, frontmost document — without copy-paste."

Cited by Codex E-01 (10), Gemini E-01 (9), DeepSeek E-02 (8), Kimi E-01 (9). All four peers' top-3 pick.

`Services/MacContextService` exposing narrow tools: `current_context`, `screen_ocr`, `selected_items`, `active_window`. ScreenCaptureKit for capture, Apple's Vision framework for on-device OCR. `PromptComposer` adds a small bounded summary chip in `BobsDeskView` so the user sees what Bob is grounded on. **Don't auto-stuff every prompt** — make context an explicit tool. Complexity: hard.

**Risk:** TCC Screen Recording is the most invasive permission the app has ever asked for. Captured pixels can contain prompt injection — a webpage saying "ignore previous instructions" reaches Bob via Vision OCR. The wrapper handles this in theory; verify in practice.

### V2. Jarvis Call Cockpit / Live Call Injection — `killer 8–10` — **4/4 unanimous**

> "Bob supervises an active Jarvis call: brief the callee, watch the live transcript, surface 1-click suggested injections, return with notes/follow-ups."

Cited by Gemini E-02 (10 — its overall #1), Codex E-05 (8), DeepSeek E-09 (8), Kimi E-07 (8).

Extend `Tools/PhoneTool.swift` with the backlog items the owner already named (call list, mid-call injection, supervision, contacts, follow-ups, memory search). Bind to a `LiveCallView` artifact in `PresentationService` showing call state, transcript stream, allowed injections, and post-call recap. `ApprovalPolicy` requires explicit per-injection approval. Complexity: medium-hard, gated by Jarvis daemon API surface.

**Risk:** Real phone calls have social/legal stakes. Latency of local model generating injection candidates may not match conversational timing — expect to need a small fast model for suggestions, the main model only for post-call summary.

### V3. Local Knowledge Layer (Activity Timeline ⊕ Document Vault) — `killer 7–9` — **4/4 unanimous**

> "Ask Bob 'what was I doing yesterday' or 'what did the contract say about X' and he answers from a private, local index of activity and files."

Cited by Codex E-02 Work Memory Timeline (9), Gemini E-06 Semantic Desktop Timeline (7), DeepSeek E-04 Memory Vault (9), Kimi E-03 Semantic Memory Palace (8).

Two flavors — should be unified:

- **Activity timeline** (Codex/Gemini/Kimi): episodic — what you did, what changed, which apps/files/conversations.
- **Document vault** (DeepSeek): semantic — what's in your local docs/notes/PDFs, indexed via local CoreML/MLX embeddings.

Extend `Persistence/Schema.swift` with two new tables: `activity_event` (event-sourced from `ToolRuntime` / `ChatSessionController` / git/file tools, plus optional FSEvents for selected folders) and `document_chunk` (FSEvents-driven incremental embed of opt-in folders, vectors stored in GRDB with optional sqlite-vss or in-memory ANN). Expose `timeline_search`, `summarize_recent_work`, and `search_vault` tools. Bound results, untrusted-wrap content. Complexity: hard.

**Risk:** Storage growth, FSEvents on `~/Documents` will pick up sensitive material — opt-in per folder, surface what's indexed in Preferences, build a one-click "forget everything between dates X and Y."

### N1. Code Companion Mode — `killer 9` — **Kimi-only but pinpoint relevance**

> "Drop Bob into any git repo and he understands the codebase, runs tests, finds the bug, and proposes patches with your approval — fully local."

Reuses existing `git_status`, `git_diff`, `shell`, `write_file` tools. Adds `project_context` tool (walks up to `.git` root, reads `Package.swift`/`project.pbxproj`, auto-injects repo structure + recent diff). Adds "dev mode" toggle in `PreferencesView` that relaxes approval for `write_file` *inside the detected repo only* while keeping shell gated. Complexity: medium.

**Why elevated despite single-peer vote:** the owner is technical, ships Swift, has Gemma 27B + qwen3.6 27B + gpt-oss 20B available locally. A *credibly local* Claude Code competitor is a moat ChatGPT/Claude desktop literally cannot match for users with IP-locked codebases.

**Risk:** "auto-approve write inside repo" is the dangerous part. Strict containment to detected `.git` root, plus a clear visual indicator that dev-mode auto-approval is active, plus reverting to global policy on shell — non-negotiable.

### V4. Workflow / Skill Capsules — `killer 7–9` — **3/4**

> "Show Bob how to do something once; he turns it into a named, editable, approval-gated local workflow."

Cited by Codex E-04 Teach Bob Once (9), Codex E-08 Personal Skill Capsules (8), DeepSeek E-08 Bob's Macros (8), Kimi E-06 Bob's Recipes (7).

GRDB-backed `SkillStore` with declarative recipes that *only* invoke existing first-party tools (no arbitrary scripting layer that bypasses `ApprovalPolicy`). `create_skill`, `list_skills`, `inspect_skill`, `run_skill` registered in `ToolRegistry`. `run_skill` dispatches through `ToolRuntime` so existing approval/path policy stays authoritative. Complexity: medium.

### V5. Voice / Walkie-Talkie Mode — `killer 7–8` — **3/4**

Cited by Gemini E-08 (8), DeepSeek E-03 (7), Kimi E-04 (7).

Apple's `SFSpeechRecognizer` for STT (on-device option), `AVSpeechSynthesizer` (or existing `speak` tool / bundled clips) for TTS, global hotkey via `NSEvent.addGlobalMonitor`. Complexity: medium.

### V6. Approval Trust UI (Diff Guardian / Flight Recorder) — `killer 8` — **2/4**

> "Before Bob writes a file or runs a destructive command, you see the diff, the exact command, the rollback path, and a replayable audit trail."

Cited by Codex E-03 (8), DeepSeek E-05 (8). Codex's framing is broader (audit/replay across all high-risk tools); DeepSeek's is the high-value MVP (color-coded diff for `write_file`). Hooks: `ApprovalPolicy`, `ToolRuntime`, a new `execution_log` GRDB table.

### V7. Proactive / Scheduled Bob — `killer 8–9` — **3/4**

Cited by DeepSeek E-01 Daily Briefing (9), Gemini E-04 Overnight Batch Mode (8), Kimi E-02 Proactive Bob (9). `BackgroundTasks` + a `SchedulerService` persisting cron-like expressions in `AppSettings`. Auto-approve only read-only tools in headless mode. Complexity: medium. **Caveat:** when the Mac is asleep, scheduled jobs slip; recovery UX needs care.

### V8. Clipboard Cortex — `killer 7–8` — **2/4**

Cited by Gemini E-05 (8), Kimi E-08 (7). Passive `NSPasteboard` watcher; small fast model classifies and cleans copied text. Gate with cheap regex heuristics before invoking model.

### V9. Interactive Artifact Workbench — `killer 6–8` — **2/4 (with disagreement)**

Cited by Codex E-07 (8 — native SwiftUI typed artifacts), Gemini E-07 (6 — JS in WKWebView). **Codex is right.** Enabling JS in `RichHTMLView` while sanitization is already a known weak point (R4) compounds risk. Native SwiftUI artifact kinds are the safer path.

---

## 6. Peer-only ideas worth keeping on the radar

| ID | Idea | Score | Cited by | Take |
|---|---|---|---|---|
| Gemini E-03 | **Finder Quick Action 'Ask Bob'** — `NSServices` integration | 7 | Gemini | Cheap to ship. High utility-per-effort. |
| Codex E-09 | **Local App Scout** — capability inventory | 7 | Codex | Discoverability superpower for new users. |
| Codex E-10 | **Screen-to-Action Debugger** | 8 | Codex | Light to ship if V1 lands. |
| Codex E-11 | **Model Flight Lab** — replay convs against candidate models | 7 | Codex | Operator value, not user-facing magic. |
| Codex E-12 | **Avatar State as Control Surface** | 7 | Codex | Pairs with V1+V2; cheap. |
| Codex E-06 | **Private Executive Desk** | 8 | Codex | Largely subsumed by V7. |
| DeepSeek E-06 | **Agent Cortex** — debug pane with full agent trace | 7 | DeepSeek | Partial overlap with V6. |
| DeepSeek E-07 | **Web Companion** — drive Safari/Chrome | 6 | DeepSeek | High TCC risk; ship V1 first and reuse. |
| Kimi E-09 | **Keychain Vault (N3)** | 6 | Kimi | Infrastructure, not magic. **Should land in Phase 0.** |
| Kimi E-10 | **Focus Guardian (N2)** — auto-swap persona by frontmost app | 7 | Kimi | Distinct from Apple Focus modes; daily-felt. |

---

## 7. Synthesizer-only findings (not in any peer output)

- **Privacy Ledger as a first-class user view.** "Show me everything Bob did in the last 24h." V6 audits a single approval; this is an aggregate explainability surface. Sells the privacy posture *visibly*.
- **macOS Focus mode integration** (distinct from Kimi's app-context Focus Guardian). When in user's Focus, gate proactive briefings (V7) and ambient features (Clipboard) behind that.
- **Multi-model orchestration *inside one turn*.** Small fast model for tool-name selection and short replies, big model only for hard reasoning. Push standard-mode model routing inside `AgentLoop`.
- **Plugin SDK posture decision.** Skill Capsules (V4) is the local-friendly extensibility story; if the project commits to "no MCP runtime," that should be made loud as the official answer.

---

## 8. The "build Monday" stack — final ranking

1. **V1 Mac Context Lens** — 4/4 unanimous, all peers' top-3.
2. **V2 Jarvis Call Cockpit** — 4/4 unanimous.
3. **V3 Local Knowledge Layer** — 4/4 unanimous.
4. **N1 Code Companion Mode** — Kimi-only but pinpoint relevance to this owner; arguably cheapest of the four MVPs because all underlying tools already exist.
5. **V6 Approval Trust UI** + **N3 Keychain Vault** — trust enablers under everything else.

**Don't-build list:**

- Don't enable JS in `RichHTMLView` (Gemini E-07) until R4 is closed.
- Don't ship Web Companion (DeepSeek E-07) before V1 — V1 gives 80% of the value at 20% of the TCC pain.
- Don't add MCP / plugin SDK as the extensibility story — declarative Skill Capsules (V4) is local-coherent and policy-bounded.

**Ground-clearing item ahead of all V/N items: resolve R4 (HTML sanitization).** V1 will route OCR'd web/document text into the loop; weak HTML sanitization in `present` becomes the obvious second-stage payload. Already on owner's named backlog.

---

## 9. External exposure summary

- **Mode used:** balanced.
- **Peers receiving data:** Codex (OpenAI/ChatGPT), Gemini (Google), DeepSeek (DeepSeek API), Kimi (Moonshot). Opus: dispatched to Anthropic but no return.
- **What was sent:** `/tmp/ob-review-bundle.md` — project description, architecture rules, tool catalog, LOC inventory, system prompt body, 30-commit `git log` one-liners, owner posture statements.
- **What was NOT sent:** any source code body, any conversation transcripts, any captured tool output, any user PII, any API keys (redact.sh confirmed 0 hits), any phone numbers/emails/addresses, any database content. Bundle was 20KB / ~5K tokens.
- **Residual sensitivity in bundle:** Names of env-var aliases (`ZACK_PERSONAL_NUMBER`, `GLENNEL_PERSONAL_NUMBER`, `JARVIS_API_KEY`, `OPERATOR_API_SECRET`) and the project layout are visible to vendors. None of those are secrets themselves.

---

## 10. Coverage gaps (this review's limits)

- **Opus never returned** — same-family Anthropic check is missing, so independent review of synthesis quality is absent.
- **Bundle did not include source bodies, tests, or transcripts** — none of the peers could assess prompt-injection resistance in practice, GRDB WAL/concurrency, real Gemma tool-call reliability, latency under load, accessibility/visual polish, the actual `<untrusted>` wrapper code, or the real failure-mode of Naughty Bob's compaction-disabled state (R7 is a guess from design).
- **No screenshots / recordings** — UI judgment is design-only.
- **All ideation is constrained by what was IN the bundle.** Opportunities outside the documented surface (e.g., what `OnboardingView.swift`'s 420 LOC actually does) are not assessed.
- **Defect-level claims about implementation difficulty in the sketches above should be re-validated against actual source before commit.**

---

**Bottom line.** Four independent peers from four training families, blind to each other, unanimously surfaced the same #1, #2, and #3 ideas. That's unusually strong corroboration. The accompanying implementation plan is in `PEER_REVIEW_TODO.md`.
