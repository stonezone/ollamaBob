# OLLAMA_CLAUDE.md — V2.5 "Make Bob Sing" Execution Plan

**Created:** 2026-04-09
**Mode:** Autonomous / parallel-agent orchestrated
**Supervisor:** Opus 4.7 (this session)
**Workers:** Sonnet 4.6 sub-agents, scope-constrained
**Drift posture:** STRICT — halt on first out-of-scope change

---

## Mission

Transform OllamaBob from "useful CLI power-tool" into "a local AI buddy you actually want to use every day." Do this without rewriting anything, without adding new libraries, and without drifting outside the 13 features listed below.

## Non-Negotiable Guardrails

These apply to every agent, every phase, every edit. The supervisor MUST halt execution if any of these is violated.

1. **In-scope features only.** The 13 features below are the complete scope. If an agent proposes adding anything else (new tool, new library, new UI concept), HALT and ask.
2. **No dependency changes.** `Package.swift` stays as-is. No new SPM packages.
3. **No file renames / deletes.** Only edits to existing files and well-scoped new files (list in §Files).
4. **Respect CLAUDE.md.** The project CLAUDE.md rules still apply (no streaming, `/api/chat` only, no write_file … WAIT — write_file is in-scope here because it's been explicitly re-authorized for this sprint; see F10).
5. **Build must pass after each phase.** `./build.sh` (no `--run`) runs before moving on. Zero errors. Warnings allowed.
6. **App must launch after final phase.** `./build.sh --run` + `pgrep -l OllamaBob` verifies.
7. **No speculative refactors.** Don't "clean up" code adjacent to the edit. Touch only what's needed.
8. **No premature abstractions.** If you're writing 3 similar lines, leave them. No helper classes for features with 1 caller.
9. **No emojis in Swift files** unless the feature explicitly ships emoji (sound icon, memory brain icon — these are allowed).
10. **No comments explaining WHAT the code does.** Comments only for WHY (non-obvious invariants).
11. **Touch only the files listed for your task.** If you need to touch a file not in your scope list, HALT and report.
12. **Every agent must report its exact diff** — "I edited X.swift lines N-M to do Y." Supervisor verifies.

## Drift Detection Protocol

After every agent returns, supervisor runs this checklist:
- [ ] Agent's reported files match actual `git diff --name-only` for that agent's phase
- [ ] No unreviewed new files in `OllamaBob/` tree
- [ ] `./build.sh` exits 0
- [ ] No new dependencies in `Package.swift` or `Package.resolved`
- [ ] No new imports beyond Foundation/SwiftUI/AppKit/Combine/GRDB

If any check fails → `git stash` the agent's changes, log a `vibe_learn` entry, and retry with tighter scope.

---

## The 13 Features (The Complete Scope)

### Tier 1 — Quick wins (feel)
- **F1. Greet on launch** — one-line persona-flavored greeting when Ollama preflight passes
- **F2. Celebrate completions** — after multi-tool chains (>2 tool calls OR >10s), Bob adds a one-line wrap-up in persona voice
- **F3. Memory indicator in status line** — `🧠 3 facts` badge that opens Memory tab on click
- **F4. Compaction notification** — inline system bubble when `ConversationCompactor` fires
- **F5. Keyboard shortcuts** — ⌘N new chat, ⌘K focus input, ⌘L clear/new, ⌘1-5 persona quick-switch
- **F6. Real-time tool feedback** — while `AgentLoop` runs a tool, show live `⚙ running: <cmd> (Ns)` in chat

### Tier 2 — Personality
- **F7. Persona-specific sprite tints** — each persona gets a subtle color overlay on the sprite
- **F8. Sound design** — two subtle sounds (send tick / receive chime), toggle in Preferences → General
- **F9. Persona leakage phrases** — small prompt additions per persona so they occasionally break filter-voice naturally

### Tier 3 — Useful
- **F10. write_file tool** — new tool, always modal approval, max 100KB, path-policy-gated
- **F11. Conversation search** — full-text LIKE search box at top of conversation manager
- **F12. Per-conversation persona quick-swap** — persona badge in chat header with popover menu
- **F13. Memory edit / import / export** — Preferences → Memory tab gains edit, delete (already exists), bulk import from markdown, export to markdown

---

## Files — Scoped Map

### New files (7)
- `OllamaBob/OllamaBob/Tools/FileWriteTool.swift` (F10)
- `OllamaBob/OllamaBob/Views/PersonaQuickSwapMenu.swift` (F12)
- `OllamaBob/OllamaBob/Views/MemoryIOPanel.swift` (F13)
- `OllamaBob/OllamaBob/Views/ConversationSearchBar.swift` (F11)
- `OllamaBob/OllamaBob/Personality/GreetingLines.swift` (F1, F2)
- `OllamaBob/OllamaBob/Sound/BobSounds.swift` (F8)
- `OllamaBob/OllamaBob/Resources/send.caf` and `receive.caf` — system sound aliases, no bundled audio files needed (use `NSSound(named:)`)

### Modified files (12)
- `OllamaBob/OllamaBob/Agent/AgentLoop.swift` — F2, F4, F6, F10 dispatch
- `OllamaBob/OllamaBob/Agent/ApprovalPolicy.swift` — F10 classification
- `OllamaBob/OllamaBob/Agent/ToolRegistry.swift` — F10 registration
- `OllamaBob/OllamaBob/Models/AppSettings.swift` — F8 sound toggle, F1 first-launch greeted flag
- `OllamaBob/OllamaBob/Personality/BobOperatingRules.swift` — F10 tool-help entry
- `OllamaBob/OllamaBob/Personality/BuiltinPersonas.swift` — F9 leakage phrases
- `OllamaBob/OllamaBob/Persistence/Database.swift` — F11 search, F13 import/export queries
- `OllamaBob/OllamaBob/Views/BobsDeskView.swift` — F1, F3, F4, F5, F6, F7, F12
- `OllamaBob/OllamaBob/Views/PreferencesView.swift` — F8 toggle, F13 edit/import/export
- `OllamaBob/OllamaBob/Views/ConversationManagerView.swift` — F11 search
- `OllamaBob/OllamaBob/Views/ChatBubble.swift` — F4 system-bubble variant, F6 live tool bubble

### Do NOT touch
- `OllamaBob/OllamaBob/OllamaBobApp.swift` unless absolutely needed for keyboard menu command
- Any `*.json` catalog files (F10 does NOT need a catalog entry — it's core, not external)
- Any `*.xcassets` (sprite tint is a `.colorMultiply` modifier, no new art)
- `Package.swift`, `Package.resolved`
- Any test files in `OllamaBobTests/`

---

## Execution Phases

### Phase 0 — Setup & Snapshot (supervisor only, ~2 min)
1. `git status` → confirm clean working tree modulo `future_features/` and `phase0/`
2. `./build.sh` → baseline build passes
3. `vibe_check` this plan before execution
4. Note starting SHA for rollback reference

### Phase 1 — Parallel Foundations (4 Sonnet agents, ~20 min)
Four agents run concurrently. They touch **disjoint files**:

| Agent | Feature | Files owned |
|-------|---------|-------------|
| A | F10 write_file | FileWriteTool.swift (new), ToolRegistry.swift, ApprovalPolicy.swift, BobOperatingRules.swift |
| B | F9 persona leakage | BuiltinPersonas.swift |
| C | F11 conversation search | Database.swift (search fn only), ConversationManagerView.swift, ConversationSearchBar.swift (new) |
| D | F13 memory I/O + edit | Database.swift (import/export fn only), PreferencesView.swift (Memory tab), MemoryIOPanel.swift (new) |

**File overlap risk:** Agents C and D both touch `Database.swift`. Mitigation: C only adds `searchMessages(query:)`; D only adds `exportFactsMarkdown()`, `importFactsMarkdown()`, `updateFact(id:content:)`. Different function blocks, append to end. Any conflict → run D after C sequentially.

**Supervisor actions after Phase 1:**
- Verify each agent's diff matches stated files
- Run `./build.sh` → must exit 0
- `vibe_check` with progress report

### Phase 2 — BobsDeskView Serial Pass (1 Sonnet agent, ~25 min)
Single agent handles all BobsDeskView edits because the file is the central UI hub and parallel edits would conflict. Features in one pass:
- F1 greet on launch (hook `AgentLoop.preflight` success → insert assistant message via `GreetingLines.forPersona`)
- F3 memory indicator (new status-line segment reading `DatabaseManager.shared.fetchFacts().count`)
- F4 compaction notification (listen for new `activityLog` entry of type `.compaction`; render as system bubble)
- F5 keyboard shortcuts (`.keyboardShortcut` on hidden buttons or `CommandMenu` in `OllamaBobApp`)
- F6 live tool bubble (new `@State var currentTool: (name, startedAt)?`, rendered when set)
- F7 persona sprite tint (apply `.colorMultiply(persona.accentColor)` to portrait)
- F12 persona quick-swap (persona badge above chat area with popover to `PersonaQuickSwapMenu`)

This agent must also create:
- `GreetingLines.swift` — dictionary `[personaID: [lines]]` with 3-5 greetings per persona
- `PersonaQuickSwapMenu.swift` — SwiftUI popover listing PersonaStore.allPersonas

**Supervisor actions after Phase 2:**
- Verify only BobsDeskView + 2 new files touched (plus possibly OllamaBobApp for CommandMenu)
- Run `./build.sh`
- `vibe_check`

### Phase 3 — Polish Parallel (2 Sonnet agents, ~15 min)

| Agent | Feature | Files owned |
|-------|---------|-------------|
| E | F8 sound design | BobSounds.swift (new), AppSettings.swift (sound toggle), PreferencesView.swift (General tab toggle) |
| F | F2 celebrate completions | AgentLoop.swift (post-tool-loop hook), GreetingLines.swift (append celebration dict) |

**File overlap risk:** Agent F and Phase 2 both touch GreetingLines.swift. Phase 2 creates the file; F appends. Ordered: F waits for Phase 2 complete.

**Supervisor actions after Phase 3:**
- Verify diffs
- `./build.sh --run` — app must launch
- `pgrep -l OllamaBob` — confirms
- Final `vibe_check`

### Phase 4 — Integration QA & Commit (supervisor, ~10 min)
1. Launch app, send test message, verify:
   - [ ] Greeting appears on launch
   - [ ] Memory count shows in status
   - [ ] Keyboard shortcuts wired
   - [ ] Persona quick-swap popover opens
   - [ ] Sounds play when toggle ON, silent when OFF
2. `git diff --stat` final review
3. `vibe_learn` a success entry
4. Commit as `feat: V2.5 — greetings, memory UI, write_file, sounds, persona polish`

---

## Agent Prompt Template (STRICT)

Every agent prompt MUST include these sections. Agents violating any get their diff reverted.

```
## Your scope
Feature: <F-number and name>
Files you may modify: <explicit list>
Files you may create: <explicit list>
Files you may NOT touch: everything else

## What to build
<Specific instructions with expected function signatures, UI layout, behavior>

## Forbidden
- Adding new SPM dependencies
- Creating files outside your owned paths
- Refactoring adjacent code
- Writing docstrings or multi-line comments
- Changing public APIs of files you don't own
- Emojis in Swift source (unless visible UI element)

## Success criteria
- Your changes compile cleanly: `cd OllamaBob && ./build.sh` exits 0
- Your reported diff matches `git diff --name-only`
- Feature works end-to-end as described

## How to report
End your work with: "DONE — modified: [files], created: [files], build status: [pass/fail]"
```

---

## Rollback Protocol

If `./build.sh` fails after any phase:
1. `git diff` to see what broke
2. If fixable in <5 min → fix directly
3. If not → `git stash` the problem diff, remove feature from scope, document in vibe_learn
4. NEVER ship a broken build to satisfy the scope

## Timeline Estimate
- Phase 0: 2 min
- Phase 1: 20 min parallel
- Phase 2: 25 min serial
- Phase 3: 15 min parallel
- Phase 4: 10 min
- **Total: ~72 min wall-clock**

---

## What We're NOT Doing (Anti-scope)

Explicitly NOT in this sprint (documented here so no agent smuggles them in):
- Screenshot / vision
- Voice I/O
- MCP client
- Scheduled briefings
- Bundled binaries (Phase 7)
- Onboarding wizard (Step 1.2c)
- Per-category approval defaults (1.4)
- Any new Ollama model integration
- Any new CLI tool catalog entries
- Any refactor of AgentLoop or OllamaClient
- Any change to GRDB schema beyond additive columns (none planned)

If an agent proposes any of these → HALT.

---

*Plan authored by supervisor. All sub-agents execute in scope or halt.*
