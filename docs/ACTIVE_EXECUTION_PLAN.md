# OllamaBob — Active Execution Plan (Post-Phase-7)

**Status:** ACTIVE — owner approved execution on 2026-04-29.
**Authorship:** Synthesized from `archive/PEER_REVIEW_2026-04-27.md` and `archive/PEER_REVIEW_TODO_2026-04-28.md` after the 2026-04-28 Codex/Kimi review pass.
**Audience:** Sonnet sub-agents executing one phase at a time without supervisor intervention.
**Authoritative ordering:** This file outranks `AGENTS.md`, `CLAUDE.md`, and `docs/CURRENT_HANDOFF.md` while present. Per `AGENTS.md` §0, an active execution plan wins.

**Supervisor note (2026-04-29):** Phase A was completed before this plan was committed into the repo. The completed integration branch is `codex/phase-bcd-kimi-integration` with Phase A commits `d145cc0`, `8e8d785`, `c4fe548`, merge commit `2e8373e`, version bump `462210c`, and final handoff commit `eb4e62a`. Continue execution from Phase B after normalizing that integration branch into local `main`.

**Supervisor note (2026-04-29, Phase B execution):** Because Phase A already shipped as `1.0.29`/`129`, Phase B ships as `1.0.30`/`130`. Final review also tightened the taint block list to include memory mutation tools (`remember`, `forget`) and `present(kind=file|url)` while keeping `present(kind=html)` allowed as read-only in-app display.

**Version note for remaining phases:** Any hard-coded future version numbers below were authored before Phase B shipped as `1.0.30`; supervisors should apply the repository version policy from the current visible version instead of treating old examples as fixed targets.

> **Read this entire file before any phase dispatch.** §0–§3 are non-negotiable. §4 contains the per-phase scope boxes, dispatch prompts, and success gates. §5–§7 govern resumption.

---

## 0. How this plan executes

### 0.1 Roles

| Role | Identity | Authority |
|---|---|---|
| **Owner** | Zack | Approves phase start. Approves merge. Can override anything in this file. |
| **Supervisor** | Claude Opus session | Cuts branches/tags. Dispatches Sonnet executor. Verifies success gate. Lands the merge. |
| **Executor** | Sonnet sub-agent | Implements one phase. Cannot commit, cannot merge, cannot push. Returns a report. |

The executor must not re-dispatch itself. The executor must not move on to the next phase under any circumstance.

### 0.2 Single-writer rule

**Never run more than one coding sub-agent at once.** Phases are sequential. Read-only Explore sub-agents may be parallel inside a single phase, but only when explicitly called for by the dispatch prompt. Cross-phase parallelism is forbidden because phases share god-class files (`AgentLoop.swift`, `BobsDeskView.swift`, `PreferencesView.swift`).

### 0.3 Branch/tag/merge protocol (non-negotiable)

```bash
# Supervisor runs these. Executor never touches git.
DATE=$(date +%Y%m%d)
PHASE_SLUG=<lowercase-kebab>            # e.g. "phase-a-hygiene"
git switch main
git pull --ff-only
git tag pre-${PHASE_SLUG}-${DATE}        # one-command revert anchor
git switch -c feature/${PHASE_SLUG}-${DATE}

# (dispatch executor against feature branch — see §5 dispatch template)

# After executor returns and verification passes:
git add -A                               # supervisor reviews diff first
git -c commit.gpgsign=false commit -m "feat(<area>): <one-line summary> (<test count>, <version>)"
git switch main
git merge --no-ff feature/${PHASE_SLUG}-${DATE} -m "Merge feature/${PHASE_SLUG}-${DATE}: <one-line>"
git tag ${PHASE_SLUG}-complete-${DATE}
git branch -d feature/${PHASE_SLUG}-${DATE}
```

The executor MUST work on the feature branch the supervisor created. The executor MUST NOT switch branches, create tags, or run any `git commit`/`git merge`/`git push`.

### 0.4 Compliance Check-in (mandatory before any code is written)

Before writing any code, the executor produces this block and stops for self-review:

```
COMPLIANCE CHECK-IN — Phase {N}

1. Top three universal STOP triggers I will respect: {S1, S5, S{phase-specific}}
2. Primary forbidden file(s): AgentLoop.swift, BobsDeskView.swift, PreferencesView.swift (unless this phase
   explicitly authorizes a delta on one of them — list the authorization here verbatim).
3. First scope-IN bullet I will start with: {bullet}
4. Test I will write first (TDD): {file path + test name}
5. LOC budget I will respect: {phase budget from §4}
6. Version bump I will perform if this phase ships user-visible behavior: {x.y.z+1 in AppConfig.swift, build.sh,
   README.md, CLAUDE.md, AGENTS.md, docs/CURRENT_HANDOFF.md}
```

If the check-in is wrong on any point, the supervisor terminates the dispatch and re-dispatches with corrections.

### 0.5 Universal STOP triggers

The executor MUST stop and ask the supervisor (by returning early with a clear status) when any of these fire:

| ID | Trigger | Reason |
|---|---|---|
| **S1** | A test fails and the failure is not understood | Silent skip is forbidden. |
| **S2** | The diff requires touching a file that is in this phase's `MAY NOT touch` list | Scope drift. |
| **S3** | The change requires changing `stream: false`, `/api/chat`, the AgentLoop pipeline, app scene/window structure, or any §1 invariant | Architecture bound. |
| **S4** | A new SPM dependency is required | Owner approval gate. |
| **S5** | LOC growth on `AgentLoop.swift`, `BobsDeskView.swift`, or `PreferencesView.swift` exceeds the phase's authorized delta | God-class concern (R1). |
| **S6** | The change would weaken or remove an existing approval/path/forbidden-shell floor | Trust-floor regression. |
| **S7** | The change would enable JS in `RichHTMLView`, add MCP/Python/Electron/Docker, or introduce streaming | Hard architecture rules. |
| **S8** | A new tool can be invoked without going through `ApprovalPolicy` and `ToolRuntime` | Bypass risk. |
| **S9** | The phase's tests pass but the executor cannot produce its Compliance Check-in retroactively | Drift detection. |
| **S10** | A required `swift build`, `swift test`, or `./build.sh` returns non-zero and the executor cannot fix it within the scope of this phase | Stop, do not skip the gate. |

### 0.6 Per-phase success gate (universal)

Every phase must satisfy:

1. `swift build` exits 0 from `OllamaBob/`.
2. `swift test` exits 0 from `OllamaBob/` with `Executed N tests, with 0 failures` and `N` strictly greater than the phase's prior count by the number of new tests claimed in the report.
3. `./build.sh` exits 0 from `OllamaBob/` and produces `build/OllamaBob.app`.
4. `git diff --check` exits 0.
5. If user-visible behavior changed: `AppConfig.appVersion`, `AppConfig.appBuild`, `build.sh`'s `CFBundleShortVersionString` and `CFBundleVersion`, `README.md`, `CLAUDE.md`, `AGENTS.md`, and `docs/CURRENT_HANDOFF.md` all reflect the new version. The `VersionConsistencyTests` test must pass.
6. `BobOperatingRules.prompt(availableToolNames:)` advertises any new tool only when registered. For phases that add tools, the dispatch prompt requires a unit test asserting this.
7. If the phase touches approval/path/shell safety, `PolicyRegressionTests` must run and pass without regression.
8. The executor's report contains: changed files list, LOC delta on protected files (must be 0 unless authorized), test count delta, scope confirmation, and the Compliance Check-in copied verbatim.

### 0.7 What the executor returns

```
EXECUTOR REPORT — Phase {N}

Branch: feature/{slug}-{date}
Files added: {paths}
Files modified: {paths}
Files deleted: {paths}
Protected-file LOC delta: AgentLoop.swift {+/-N}, BobsDeskView.swift {+/-N}, PreferencesView.swift {+/-N}
Test count delta: {prior} → {new}
swift build: PASS
swift test: PASS — {N} tests, 0 failures
./build.sh: PASS — bundle CFBundleShortVersionString={X.Y.Z} CFBundleVersion={X}
git diff --check: PASS
Version bumped: {yes|no, if yes new version}
Compliance Check-in (verbatim from start of session): {block}
Open questions for supervisor: {list or "none"}
```

The supervisor does not commit until this report is produced and verified.

---

## 1. Preserved invariants (carried into every phase)

These are non-negotiable. STOP S3 fires the moment a change requires touching them.

1. Native `/api/chat`. Never `/v1/chat/completions`.
2. `stream: false`.
3. Swift-owned `AgentLoop`. No Python, Electron, Docker, MCP, or external agent runtime.
4. `AgentLoop → ChatSessionController → BobsDeskView` flow.
5. `ApprovalPolicy` and `PathPolicy` are non-bypassable floors. Per-tool `Auto`/`Ask`/`Deny` overrides may *raise* approval requirements but never *lower* them past the floor.
6. Forbidden shell-command shape detection.
7. Jarvis dual-secret auth (`X-Jarvis-Key` + `x-operator-secret`).
8. Flat tool parameter schemas.
9. SQLite via GRDB for persistence. Migrations are additive only.
10. Native approval dialogs (`ApprovalAlert`, `NSAlert`).
11. App scene/window structure preserved (the eight `Window(...)` declarations in `OllamaBobApp.swift`). New windows are additive.
12. `<untrusted>` wrapper for any tool output that may carry adversarial content.
13. No JS in `RichHTMLView`. No new ports/sockets/listeners exposed by the app.
14. `BobOperatingRules.prompt(availableToolNames:)` is the source of truth for the tool inventory shown to the model.

---

## 2. Phase ordering rationale

Tier 1: hygiene + R2 trust floor must land before V3 because V3 routes web-search and document content into the loop, where R2 becomes load-bearing.

Tier 2: Phase 8 (BobsDeskView decomposition) lands before V9 (artifact workbench) because the artifact surface needs a clean home in the desk view.

Tier 3: V3 sub-phases run in the owner-approved Order A (timeline first, then vault) per `archive/PHASE_5_PLAN_2026-04-28.md`.

Tier 4: R7 (Naughty Bob compaction) and Tier-4 quick wins are interleaved as palate cleansers between Tier-1 and Tier-3 phases so the executor doesn't burn out on V3 schema work.

---

## 3. Phase index

| Phase | Title | Tier | Est LOC | Authorized protected-file delta |
|---|---|---|---|---|
| **A** | Hygiene — commit Codex, fix Kimi K1, merge Kimi | 0 | ≤ 100 | none |
| **B** | R2 — Untrusted Taint Policy | 1 | ≤ 350 | AgentLoop.swift +20 max |
| **C** | Phase 8 — BobsDeskView decomposition | 2 | ≤ 600 net | BobsDeskView.swift may shrink up to 800 LOC |
| **D.1** | V3 Schema + ActivityEvent value type | 3 | ≤ 250 | none |
| **D.2** | V3 ActivityIndexer (tool + chat sources) | 3 | ≤ 200 | AgentLoop.swift +5 max, BobsDeskView.swift +0 |
| **D.3** | V3 FSEvents source (opt-in folders) | 3 | ≤ 350 | PreferencesView.swift +60 max |
| **D.4** | V3 Document Vault schema + chunker | 3 | ≤ 400 | none |
| **D.5** | V3 `timeline_search` tool | 3 | ≤ 250 | none |
| **D.6** | V3 `search_vault` tool | 3 | ≤ 350 | none |
| **D.7** | V3 `summarize_recent_work` tool | 3 | ≤ 200 | none |
| **E** | R7 — Naughty Bob compaction budget banner | 2 | ≤ 200 | BobsDeskView.swift +30 max |
| **F.1** | V9 Native artifact kinds + ArtifactStore | 2 | ≤ 250 | none |
| **F.2** | V9 TableArtifactView | 2 | ≤ 200 | none |
| **F.3** | V9 ChecklistArtifactView | 2 | ≤ 200 | none |
| **F.4** | V9 DiffArtifactView | 2 | ≤ 200 | none |
| **F.5** | V9 CodeArtifactView | 2 | ≤ 200 | none |
| **F.6** | V9 FileTreeArtifactView | 2 | ≤ 200 | none |
| **F.7** | V9 `present(kind=artifact)` integration | 2 | ≤ 250 | BobsDeskView.swift +20 max |
| **G** | Privacy Ledger aggregate view | 3 | ≤ 250 | none |
| **H** | Multi-model orchestration | 3 | ≤ 400 | AgentLoop.swift +60 max |
| **I.1** | Finder Quick Action (NSServices) | 4 | ≤ 200 | none |
| **I.2** | App Scout tool | 4 | ≤ 200 | none |
| **I.3** | Avatar State as Control Surface | 4 | ≤ 250 | BobsDeskView.swift +30 max |
| **I.4** | Screen-to-Action Debugger | 4 | ≤ 250 | none |

Default order: A → B → C → D.1 → D.2 → D.5 → E → F.1 → F.2..F.6 → F.7 → D.3 → D.4 → D.6 → D.7 → G → H → I.1 → I.2 → I.3 → I.4. Owner can reorder Tier 4. Tier 1 and 2 are sequential.

---

## 4. Phases

### Phase A — Hygiene

**Why first.** The Codex branch is uncommitted and the Kimi worktree has a behavioral regression (K1: shell stdout kill limit). Nothing else can be safely supervised until the working tree is clean and Kimi is mergeable.

#### A.1 — Commit the Codex branch as it stands

**Files MAY modify:** none (commit-only).
**Files MAY NOT touch:** all source files. This is a pure git step.
**MUST add (already untracked):** `archive/HANDOFF_TO_CODEX_2026-04-28.md`, `archive/PEER_REVIEW_2026-04-27.md`, `archive/PEER_REVIEW_TODO_2026-04-28.md`, `archive/PHASE_5_PLAN_2026-04-28.md`, `OllamaBob/OllamaBob/Models/DeskPromptInbox.swift`, `OllamaBob/OllamaBob/Views/DeskPromptActions.swift`, `OllamaBob/Tests/OllamaBobTests/DeskPromptActionsTests.swift`.

**Sub-agent dispatch prompt (verbatim):**

```
You are executing Phase A.1 of OllamaBob's docs/ACTIVE_EXECUTION_PLAN.md. Read that file in full
before doing anything. You are operating on branch feature/phase-a-hygiene-{date} which is already
created and checked out for you on top of the existing uncommitted Codex changes.

You are NOT allowed to write a single line of code or edit a single file in this dispatch.
You ARE allowed to run git commands.

Tasks, in order:
1. Run `cd /Users/zack/ollamaBob && git status` and verify the file list matches the expected
   uncommitted set in §A.1. If any extra file is present (especially anything containing secrets:
   .env, *.key, credentials*), STOP and report. If anything is missing, STOP and report.
2. Run `cd /Users/zack/ollamaBob/OllamaBob && swift build && swift test && ./build.sh && cd .. && git diff --check`.
   All four must pass. If any fail, STOP — do not commit anything.
3. Stage exactly the files in §A.1's "MUST add" list plus the modified files in §A.1's "Files modified" list
   from `git status`. Use `git add <path>` per file. Do NOT use `git add -A` or `git add .`.
4. Verify nothing else is staged: `git diff --cached --name-only` must match exactly the union of "MUST add"
   and the modified-file list.
5. Produce the commit message via heredoc (no inline -m):

   git commit -c commit.gpgsign=false -F - <<'EOF'
   feat(phase-bcd): Jarvis HTTP integration, dynamic prompt, desk status strip, brave-key UI

   - Jarvis call supervision: real /calls/active, /call/status/:id, /call/:id/message
     routes via JarvisCallClientHTTP with the dual-secret contract
   - LiveCallView injection now goes through ApprovalPolicy + ApprovalAlert + PhoneInjectTool
     and writes to the Privacy Ledger; 5s transcript polling while window open
   - DeskPromptInbox + DeskPromptActions adapter: clipboard stack traces and walkie-talkie
     transcripts queue safely until BobsDeskView mounts; clipboard stack traces are
     untrusted-wrapped before injection
   - BobsDeskView desk status strip surfacing Mac context, Code Companion, walkie-talkie,
     and Focus Guardian state
   - BobOperatingRules.prompt(availableToolNames:) renders the live tool inventory; phone
     supervision rules gated on registered phone tools rather than only PhoneTool.isConfigured
   - BriefingRunner synthesis prompt now explicitly tells the model to treat <untrusted>
     blocks as data, not instructions (regression-tested)
   - SecretMigration.defaultConfirm shows pending key-by-key details before migration
   - PreferencesView: Web Search section with Keychain-backed Brave key + .env import,
     Daily Briefing controls (enable/time/run-now), DEBUG-only mocked-Jarvis-client toggle
   - DEBUG default for useMockedJarvisClient flipped to false; release was already false
   - Briefing History window added to menu bar
   - Docs cleanup: peer-review and Phase 5 plan moved to archive/, current handoff refreshed
   - Version 1.0.27 → 1.0.28
   EOF

6. After commit, run `git status` and report. The working tree should be clean (only the
   kimi-export-*.md untracked file from the Kimi worktree remains, if visible).
7. Re-run the four verification commands from step 2. All must pass.
8. Return the EXECUTOR REPORT in §0.7 format.

You may NOT push, merge, or tag. The supervisor will tag and merge this branch.

If you encounter a pre-commit hook failure, do NOT use --no-verify. STOP and report.
```

**Success gate (A.1):** Commit lands cleanly. Verification commands all pass. Working tree clean.

#### A.2 — Fix Kimi K1 (ShellTool kill limit)

This phase operates on the Kimi worktree at `/Users/zack/ollamaBob-kimi-phase-a` on branch `codex/kimi-phase-a-security`.

**Files MAY modify:**
- `OllamaBob/OllamaBob/Tools/ShellTool.swift`
- `OllamaBob/OllamaBob/AppConfig.swift` (add a single new constant only)
- `OllamaBob/Tests/OllamaBobTests/PolicyRegressionTests.swift` (one new test only)

**Files MAY NOT touch:** every other file in the repo.

**Sub-agent dispatch prompt (verbatim):**

```
You are executing Phase A.2 of OllamaBob's docs/ACTIVE_EXECUTION_PLAN.md. Read that file in full
before doing anything. You are working in /Users/zack/ollamaBob-kimi-phase-a on branch
codex/kimi-phase-a-security.

The Kimi Phase A pass introduced a behavioral regression in ShellTool: it passes
AppConfig.shellStdoutMax (10_000 bytes) as the process-kill stdout cap to ProcessRunner.run,
and AppConfig.shellStderrMax (2_000 bytes) as the stderr cap. Those constants were originally
the *display-truncation* limits used by OutputLimits.truncateShellStdout/Stderr. Reusing them
as kill caps means any shell command producing more than 10 KB of stdout (`git log`, `seq 1 50000`,
album scripts, ffmpeg progress) is terminated mid-run and returned as .failure with
"[output limit exceeded]". This is too aggressive.

Your task:

1. Produce the COMPLIANCE CHECK-IN (§0.4 of the plan). Stop and self-review.

2. TDD: add ONE test to OllamaBob/Tests/OllamaBobTests/PolicyRegressionTests.swift named
   `testShellToolToleratesOutputLargerThanShellDisplayCap`. The test runs
   `ShellTool.execute(command: "for i in $(seq 1 5000); do echo line_$i; done")` and asserts:
     - result.success == true
     - result.content does not contain "[output limit exceeded]"
     - result.content's length is bounded (truncated for display) but ≤ 11_000 chars
       (one chunk past shellStdoutMax of 10_000).
   Run `swift test --filter PolicyRegressionTests/testShellToolToleratesOutputLargerThanShellDisplayCap`.
   Verify it FAILS with the current ShellTool. If it passes, your TDD is wrong — STOP.

3. In OllamaBob/OllamaBob/AppConfig.swift add ONE new constant near the existing process limits:
       static let shellProcessKillBytes = 1_000_000   // 1 MB hard kill cap; display truncation
                                                      // uses shellStdoutMax / shellStderrMax.
   Do not modify any other constant. Do not bump the app version.

4. In OllamaBob/OllamaBob/Tools/ShellTool.swift change the two ProcessRunner.run arguments:
       stdoutMaxBytes: AppConfig.shellProcessKillBytes,
       stderrMaxBytes: AppConfig.shellProcessKillBytes,
   Leave OutputLimits.truncateShellStdout / truncateShellStderr unchanged so display truncation
   continues to use the existing 10 KB / 2 KB limits.

5. Run the full test suite from /Users/zack/ollamaBob-kimi-phase-a/OllamaBob:
       swift build
       swift test
       ./build.sh
       cd .. && git diff --check
   All four must pass and the prior 378 test count must be 378 + 1 = 379.

6. Return the EXECUTOR REPORT in §0.7 format. You may NOT commit. Supervisor commits.

STOP TRIGGERS specific to this phase (in addition to the universal §0.5 set):
- Touching any file outside the three listed under "Files MAY modify".
- Adding more than one constant to AppConfig.swift.
- Modifying OutputLimits.swift, ProcessRunner.swift, or any test file other than
  PolicyRegressionTests.swift.
- Reducing shellStdoutMax / shellStderrMax (those govern *display*, not killing).
```

**Success gate (A.2):** 379 tests pass; new test specifically passes; ShellTool change is exactly the two-line argument flip plus AppConfig constant addition; no other diff.

#### A.3 — Merge Kimi into main, then merge into the Codex follow-up branch

Supervisor-only step. Two-stage merge:

```bash
# Stage 1: merge Kimi into main
git switch main
git pull --ff-only
git tag pre-kimi-phase-a-merge-$(date +%Y%m%d)
cd /Users/zack/ollamaBob-kimi-phase-a
git -c commit.gpgsign=false commit -am "fix(shell): use 1 MB kill cap; keep 10 KB display truncation (379 tests)"
cd /Users/zack/ollamaBob
git fetch /Users/zack/ollamaBob-kimi-phase-a codex/kimi-phase-a-security:codex/kimi-phase-a-security
git merge --no-ff codex/kimi-phase-a-security -m "Merge Kimi Phase A: shell/file/path TOCTOU + tokenized parsing (379 tests)"
# Resolve trivial conflict in AppConfig.swift (version 1.0.28 + processOutputMaxBytes + shellProcessKillBytes coexist).

# Stage 2: re-verify
cd OllamaBob
swift build && swift test && ./build.sh
git diff --check

# Stage 3: tag
git tag kimi-phase-a-complete-$(date +%Y%m%d)
```

**Success gate (A.3):** main contains both Codex and Kimi work. Test count is 382 (Codex's count) plus the new tests Kimi added on top of its base — verify the actual delta from the merged tree, do not assume 382 + 379. Any conflict resolution must be in `AppConfig.swift` only; if other files conflict, STOP and reconcile manually.

#### A.4 — Refresh handoff after Phase A

**Files MAY modify:** `docs/CURRENT_HANDOFF.md` only.

The supervisor updates the handoff to reflect: (a) Codex+Kimi merged, (b) version 1.0.28, (c) plan-driven future work points to this file.

---

### Phase B — R2 Untrusted Taint Policy

**Why now.** R2 from the peer review remains the single largest unaddressed security gap. Today the `<untrusted>` wrapper is a *prompt instruction*, not a *policy boundary*. Phase B turns it into a real boundary: a turn whose context contains untrusted content cannot invoke a hard-coded set of side-effecting tools on the *next* model turn unless the user explicitly re-prompts. This is a precondition for V3 (which routes web-search and document content into the loop).

**Tools subject to taint:** `shell`, `applescript`, `phone_call`, `phone_inject`, `clipboard_write`, `youtube_download`, `write_file`, `move_file`, `create_directory`, `image_convert`, `mail_triage` (writes a draft preview), `run_skill` (recursively).
**Tools NOT subject to taint** (read-only): `read_file`, `list_directory`, `search_files`, `git_status`, `git_diff`, `web_search`, `weather`, `unit_convert`, `ocr`, `clipboard_read`, `remember`, `forget`, `list_facts`, `phone_status`, `phone_list_calls`, `phone_get_transcript`, `active_window`, `selected_items`, `screen_ocr`, `current_context`, `tool_help`, `read_tool_output`, `project_context`, `present` (read-only display).

**Tainting sources** (any tool whose output may contain adversarial text from third parties):
`web_search`, `screen_ocr`, `mail_check`, `mail_triage`, `clipboard_read`, `read_file`, `youtube_search`, briefing-tool aggregations, V3 `timeline_search` and `search_vault` (when they ship), and any `<untrusted>`-wrapped content.

**Files MAY add:**
- `OllamaBob/OllamaBob/Agent/TaintPolicy.swift`
- `OllamaBob/Tests/OllamaBobTests/TaintPolicyTests.swift`

**Files MAY modify:**
- `OllamaBob/OllamaBob/Agent/AgentLoop.swift` — add ≤ 20 LOC: a single hook in the tool-dispatch path that consults `TaintPolicy.tainted(forSession:)` before invoking a side-effecting tool. The decision must short-circuit `BEFORE` `ApprovalPolicy.check` runs, returning a deterministic refusal `ToolResult` and posting a banner notification.
- `OllamaBob/OllamaBob/Agent/AgentLoopToolDispatch.swift` — only the function that the AgentLoop hook calls; no other change.
- `OllamaBob/OllamaBob/Models/UntrustedWrapper.swift` — extend with a `Source` enum value type so `BriefingRunner`, `read_file`, etc., can record which source tainted the session.
- `OllamaBob/OllamaBob/Personality/BobOperatingRules.swift` — add a new "Taint" section to the system prompt that explains the rule to the model (≤ 30 LOC).
- `OllamaBob/OllamaBob/Views/BobsDeskView.swift` — add ≤ 20 LOC: a banner row above the input that reads "Untrusted content in this turn — write actions disabled. Type `/lift` to clear." This row is only visible when `TaintPolicy.tainted == true`.

**Files MAY NOT touch:** every test file other than the new `TaintPolicyTests.swift`. Every other Swift file. Every doc except `docs/CURRENT_HANDOFF.md` and the version-bump set.

**Required tests (≥ 12):**

1. `testTaintPolicyMarksSessionTaintedAfterWebSearch`
2. `testTaintPolicyMarksSessionTaintedAfterScreenOCR`
3. `testTaintPolicyMarksSessionTaintedAfterMailCheck`
4. `testTaintPolicyMarksSessionTaintedAfterReadFile`
5. `testTaintPolicyDoesNotTaintAfterReadOnlyTools` (assert `git_status`, `weather` etc. don't flip the bit)
6. `testTaintPolicyBlocksShellWhenTainted`
7. `testTaintPolicyBlocksWriteFileWhenTainted`
8. `testTaintPolicyBlocksPhoneInjectWhenTainted`
9. `testTaintPolicyDoesNotBlockReadOnlyToolsWhenTainted` (read tools still work after taint)
10. `testTaintPolicyClearsOnUserMessage` (when the next message is from the user, the session lifts; this is the "explicit re-prompt" semantic)
11. `testTaintPolicyClearsOnSlashLiftCommand`
12. `testTaintPolicyAttachesSourceMetadataToBlockedResult` (the refusal `ToolResult.content` names which source tainted the session — `web_search`, `screen_ocr`, etc.)

**Sub-agent dispatch prompt (verbatim):**

```
You are executing Phase B of OllamaBob's docs/ACTIVE_EXECUTION_PLAN.md. Read that file in full
before doing anything. You are working on branch feature/phase-b-untrusted-taint-{date}.

Before any code, return the COMPLIANCE CHECK-IN block (§0.4) and stop for one beat.

Implement R2 Untrusted Taint Policy exactly per §B of the plan. Hard rules:

1. Add OllamaBob/OllamaBob/Agent/TaintPolicy.swift containing a @MainActor enum or singleton with:
     - `tainted(forSession id: String) -> Bool`
     - `markTainted(forSession id: String, source: TaintSource)`
     - `lift(forSession id: String)`
     - A `decision(toolName: String, sessionID: String) -> TaintDecision` function returning either
       `.allow` or `.blockedBy(TaintSource)`. The blocked list is hard-coded per §B (shell, applescript,
       phone_call, phone_inject, clipboard_write, youtube_download, write_file, move_file,
       create_directory, image_convert, mail_triage, run_skill).
     - Internal storage: in-memory dictionary keyed by ChatSessionController.id (do NOT persist to GRDB —
       taint is per-session and resets on app restart).
     - The decision must be testable without spinning up the full AgentLoop.

2. Add the AgentLoop hook in AgentLoopToolDispatch.swift exactly once, before ApprovalPolicy.check:
       if case .blockedBy(let source) = TaintPolicy.shared.decision(toolName: name, sessionID: sessionID) {
           return ToolResult.denied(tool: name,
               reason: "This tool is unavailable while the conversation contains untrusted content from \(source.displayName). Send a new message or type /lift to clear.")
       }
   The +20 LOC budget on AgentLoop.swift is for the wiring needed to thread sessionID into the dispatch
   call. Do not exceed that budget. If threading sessionID requires more than 20 LOC, STOP — re-architect
   so AgentLoopToolDispatch already has access to it.

3. Tainting sources call TaintPolicy.shared.markTainted right after their successful tool execution.
   For BriefingRunner, mark taint on the briefing-result conversation; for normal tool dispatch, mark
   taint when the tool returns success and is in the §B "Tainting sources" list. Do not mark on failure.

4. Lifting: a user message arriving via ChatSessionController flips lift. The "/lift" command is parsed
   in AgentLoop's user-message preflight (existing slash-command surface — keep additive, do not refactor
   the slash-command parser; just add one case).

5. UntrustedWrapper.swift gains a TaintSource enum and a wrap(_:source:) overload. The old wrap(_:) keeps
   working (back-compat) and defaults source = .unknown.

6. BobOperatingRules: add a new "Untrusted content" section that the prompt only renders when the session
   is tainted (BobOperatingRules.prompt currently takes availableToolNames? — extend to also take
   `taintActive: Bool = false`). When true, the section says: write/destructive tools are blocked this
   turn; advise the user to send a fresh message to lift.

7. BobsDeskView banner: 20 LOC max. Show only when TaintPolicy says tainted == true. Use the existing
   warning-styled chip surface in the desk status strip, placed above the input row.

8. Run all 12 tests in TaintPolicyTests.swift. They MUST all be RED before the implementation, and GREEN
   after. Provide a paste of the pre-implementation red output and the post-implementation green output
   in the EXECUTOR REPORT.

9. Run the full success gate (§0.6). Bump version to 1.0.30 (build 130) and update all six version files.

STOP TRIGGERS specific to Phase B:
- The AgentLoop.swift LOC delta exceeds +20.
- Any change weakens an existing approval/path/forbidden-shell floor (S6).
- Tainting is persisted to GRDB (not allowed; per-session in-memory only).
- The "/lift" command is added to the model-callable tool surface (it must be a user-only slash command,
  invisible to the model and the registry).
- The TaintPolicy hook runs AFTER ApprovalPolicy instead of BEFORE.
- Read-only tools (per §B "Tools NOT subject to taint" list) become blockable.
```

**Success gate (B):** 12 new tests green; AgentLoop.swift LOC delta ≤ +20; banner visible only when tainted; `/lift` clears; version bumped to 1.0.30; PolicyRegressionTests still green.

---

### Phase C — Phase 8 BobsDeskView Decomposition

**Why now.** BobsDeskView is ~1700 LOC. Phases F (artifact workbench) and E (compaction banner) need clean homes inside the desk surface. Decomposition first lets later phases stay small.

**Decomposition target.** Extract three subviews and one view-model:

1. `OllamaBob/OllamaBob/Views/Desk/DeskTranscriptView.swift` — the transcript ScrollView + message rendering.
2. `OllamaBob/OllamaBob/Views/Desk/DeskInputView.swift` — the input row (text field, send button, attachment chip handling).
3. `OllamaBob/OllamaBob/Views/Desk/DeskStatusStrip.swift` — extract the existing `deskStatusStrip` ViewBuilder into its own file.
4. `OllamaBob/OllamaBob/Models/Desk/DeskViewModel.swift` — `@MainActor` ObservableObject owning: bubble visibility, breath phase, history overlay, drainPendingDeskPrompts, stageOrSendInjectedPrompt. BobsDeskView passes `agentLoop` and `session` in; the view-model exposes published state.

After the split, BobsDeskView.swift must be ≤ 800 LOC and only contain the top-level layout (portrait + status strip + transcript + input) plus the lifecycle hooks that bind to DeskViewModel.

**Files MAY add:** the four files listed above plus a new `Tests/OllamaBobTests/DeskViewModelTests.swift` (≥ 6 tests).

**Files MAY modify:**
- `OllamaBob/OllamaBob/Views/BobsDeskView.swift` — must SHRINK by at least 800 LOC.
- `OllamaBob/Package.swift` — only if a new `Sources/` subdirectory needs registration (likely not).

**Files MAY NOT touch:** every other Swift file. No persistence migration. No tool registry change. No prompt change.

**Required tests:**

1. `testDeskViewModelDrainsPendingPromptsOnAppear`
2. `testDeskViewModelStageOrSendInjectedPromptDoesNotSendWhenAgentBusy`
3. `testDeskViewModelHistoryOverlayToggle`
4. `testDeskViewModelObservesMacContextStore` (changing `MacContextStore.shared.lastContext` flips a published property)
5. `testDeskViewModelHandlesWalkieTalkieTranscript`
6. `testDeskViewModelHandlesClipboardStackTraceRequest`

**Sub-agent dispatch prompt (verbatim):**

```
You are executing Phase C of OllamaBob's docs/ACTIVE_EXECUTION_PLAN.md. Read that file in full
before doing anything. You are working on branch feature/phase-c-deskview-decomp-{date}.

Goal: extract three subviews and one view-model from BobsDeskView.swift while preserving every
behavior. After the split, BobsDeskView.swift must be ≤ 800 LOC and exclusively orchestrate
top-level layout + lifecycle.

Before any code, return the COMPLIANCE CHECK-IN block. Note that this phase EXPLICITLY authorizes
shrinking BobsDeskView.swift; the protected-file delta budget is "may shrink up to 800 LOC; may
NOT grow."

Hard rules:
1. The extraction MUST be behavior-preserving. Run swift test BEFORE any extraction; record the
   number. Run it after each extracted subview and confirm the same number passes.
2. DeskViewModel must be a @MainActor ObservableObject. It owns no AppKit views, only state.
3. DeskViewModelTests must NOT spin up the full SwiftUI hierarchy. They construct the view-model
   directly with stubs (a stub AgentLoop is acceptable; if AgentLoop cannot be stubbed cheaply,
   inject only the bits the view-model needs via a small protocol).
4. Notification subscriptions move WITH the view-model — DeskViewModel becomes the single sink for
   .bobWalkieTalkieTranscript, .clipboardCortexSummarizeStackTrace, .bobDeskPromptAvailable. Remove
   the duplicate subscriptions from BobsDeskView.swift.
5. The desk status strip ViewBuilder logic must move to DeskStatusStrip.swift unchanged. The
   `shouldShowDeskStatusStrip` predicate moves with it.
6. After extraction, BobsDeskView.swift contains: top-level View struct, the body assembling
   `portraitSection`, `DeskStatusStrip(...)`, `DeskTranscriptView(...)`, `DeskInputView(...)`,
   plus the .onAppear and .onReceive plumbing that calls into DeskViewModel.
7. Do NOT change any persona, avatar, animation, or prompt code. Do NOT touch ChatSessionController.
   Do NOT touch AgentLoop. Do NOT touch any tool.
8. Do NOT add a SwiftUI Preview unless it already exists. If you add one, gate it behind #if DEBUG.
9. After all extractions, run swift test and confirm test count = (prior count) + 6. Run swift build,
   ./build.sh, git diff --check.
10. Bump version to 1.0.30 (build 130) — this is internal-quality but counts as user-visible because
    the desk surface is the primary UI; per §0.6 rule 5, bump.

STOP TRIGGERS specific to Phase C:
- Any test fails at any extraction step. Roll back the most recent extraction and STOP.
- BobsDeskView.swift LOC after extraction exceeds 800 (i.e. the split was insufficient).
- Any non-decomposition behavior change appears in the diff (different padding, animation timing,
  font, color, ordering).
- DeskViewModel acquires a strong ref to a UI surface (NSWindow, View) — must remain pure state.
- Notification subscriptions duplicated between BobsDeskView and DeskViewModel.

Return EXECUTOR REPORT in §0.7 format with the BobsDeskView.swift before/after LOC count.
```

**Success gate (C):** BobsDeskView.swift ≤ 800 LOC, four new files, 6 new tests green, all prior tests green, version 1.0.30. No behavior change visible to the user.

---

### Phase D — V3 Local Knowledge Layer

Per `archive/PHASE_5_PLAN_2026-04-28.md` Order A. Each sub-phase ships behind a Preferences toggle defaulting OFF. No surprise indexing.

#### D.1 — Schema + ActivityEvent value type

**Files MAY add:**
- `OllamaBob/OllamaBob/Models/ActivityEvent.swift` — value type.
- `OllamaBob/Tests/OllamaBobTests/ActivityEventDatabaseTests.swift` — ≥ 6 tests.

**Files MAY modify:**
- `OllamaBob/OllamaBob/Persistence/Schema.swift` — additive `activity_event` table + indices per Phase-5 plan §5.1.
- `OllamaBob/OllamaBob/Persistence/Database.swift` — `appendActivityEvent(...)` and `fetchActivityEvents(since:until:source:limit:)`.

**Files MAY NOT touch:** every other file.

**Required tests:**

1. `testActivityEventRoundtrip`
2. `testActivityEventTimestampIndexUsedByRangeQuery` (assert query plan via EXPLAIN — or equivalent — uses `idx_activity_event_timestamp`)
3. `testActivityEventSourceKindIndexUsedByFilterQuery`
4. `testActivityEventDetailTruncatedAt500Chars`
5. `testActivityEventMetadataJSONCappedAt1KB`
6. `testActivityEventConcurrentAppendIsThreadSafe` (10 concurrent inserts, all succeed, count == 10)

**Sub-agent dispatch prompt (verbatim):**

```
You are executing Phase D.1 of OllamaBob's docs/ACTIVE_EXECUTION_PLAN.md. Read that file plus
archive/PHASE_5_PLAN_2026-04-28.md §5.1 in full before doing anything.

Before any code, return the COMPLIANCE CHECK-IN block.

Implement the activity_event table additively in OllamaBob/OllamaBob/Persistence/Schema.swift.
The migration MUST be additive: do not modify any existing table, do not drop, do not rename.
Use GRDB's existing migration registration pattern in this project — read Schema.swift first to
match style. Migration name MUST start with the next sequential id available.

Add two GRDB DAO methods on Database (or DatabaseManager — match the existing style):
   func appendActivityEvent(_ event: ActivityEvent) throws -> Int64
   func fetchActivityEvents(since: Date, until: Date,
                            source: String? = nil, kind: String? = nil,
                            limit: Int = 100) throws -> [ActivityEvent]

ActivityEvent fields (per §5.1):
   id (Int64?, nil before insert)
   timestamp (Date)
   source ("tool" | "chat" | "fsevents")
   kind (String, e.g. "tool_call", "user_message", "file_changed")
   detail (String, capped 500 chars in the appender)
   conversationID (String?)
   metadataJSON (String?, capped 1024 bytes in the appender)

The appender MUST:
   - Truncate detail to 500 chars before insert (no exception, just truncate).
   - Reject metadataJSON > 1024 bytes by throwing — do not silently truncate JSON.

Tests are listed in §D.1. Write each test BEFORE its production code (TDD). Run swift test --filter
ActivityEventDatabaseTests after each test to confirm red → green.

No new tool. No new UI. No version bump (this is a hidden additive schema change; D.2 ships the
first user-facing toggle). The 1.0.30 → 1.0.30 version stays.

STOP TRIGGERS specific to Phase D.1:
- Any modification to an existing schema table or migration.
- A non-sequential migration id.
- Use of try! in production code (use throws and propagate).
- Tests that hit the production GRDB database; they must use an in-memory or temp-file db.

Return EXECUTOR REPORT.
```

**Success gate (D.1):** 6 new tests green; total test count rises by 6; schema migration is additive and named with the next sequential id; no UI change.

#### D.2 — ActivityIndexer (tool + chat sources)

**Files MAY add:**
- `OllamaBob/OllamaBob/Services/ActivityIndexer.swift` — `@MainActor` singleton.
- `OllamaBob/Tests/OllamaBobTests/ActivityIndexerTests.swift` — ≥ 5 tests.

**Files MAY modify:**
- `OllamaBob/OllamaBob/Models/AppSettings.swift` — add `activityTimelineEnabled: Bool` (default `false`) plus the persisted-key constant. ≤ 15 LOC.
- `OllamaBob/OllamaBob/Agent/AgentLoopToolDispatch.swift` — single line in the post-execution path: `ActivityIndexer.shared.recordToolCall(name: name, success: result.success, conversationID: sessionID)`. ≤ 5 LOC.
- `OllamaBob/OllamaBob/Models/ChatSessionController.swift` — single line in the user-message persistence path and the assistant-message persistence path: `ActivityIndexer.shared.recordChatMessage(role: ..., conversationID: ...)`. ≤ 6 LOC total.
- `OllamaBob/OllamaBob/Views/PreferencesView.swift` — new toggle row in an existing section. ≤ 30 LOC.

**Files MAY NOT touch:** AgentLoop.swift body (only AgentLoopToolDispatch.swift), BobsDeskView.swift, every other view.

**Required tests:**

1. `testActivityIndexerNoOpWhenToggleOff`
2. `testActivityIndexerRecordsToolCallWhenOn`
3. `testActivityIndexerRecordsUserMessage`
4. `testActivityIndexerRecordsAssistantMessage`
5. `testActivityIndexerCapsDetailLength`

**Sub-agent dispatch prompt (verbatim):**

```
You are executing Phase D.2 of docs/ACTIVE_EXECUTION_PLAN.md. Read that file plus
archive/PHASE_5_PLAN_2026-04-28.md §5.2 first.

Compliance Check-in then implement.

ActivityIndexer.shared is a @MainActor singleton with three methods:
   func recordToolCall(name: String, success: Bool, conversationID: String?)
   func recordChatMessage(role: String, conversationID: String?, summary: String?)
   func recordFileEvent(path: String, kind: String)   // stub for D.3 — empty body for now
Each method is a no-op when AppSettings.shared.activityTimelineEnabled == false. When true, each
appends an ActivityEvent via Database.appendActivityEvent.

Wire the call sites EXACTLY where listed in §D.2 "Files MAY modify". The +5 LOC budget on
AgentLoopToolDispatch.swift is hard. If you need more, STOP — pass the conversationID through
the existing dispatch context.

Add a Preferences toggle "Activity Timeline (local)" in the existing General section. The toggle
copy: "Record tool calls and chat messages locally so Bob can answer 'what was I doing?'. Stays on
your Mac. Default OFF." Off by default. Persisted via UserDefaults key "activityTimelineEnabled".

Tests use a stub or in-memory database. Do NOT exercise the real GRDB database from tests.

No new tool yet — D.5 (timeline_search) is when the model gets to query this.

Bump version to 1.0.31. Run the full success gate (§0.6).

STOP TRIGGERS specific to Phase D.2:
- AgentLoop.swift body modified (only AgentLoopToolDispatch.swift may change).
- ActivityIndexer made non-MainActor.
- Default toggle is on. Default MUST be off.
- Any indexing happens before the toggle is checked.
- Recording adds latency to the tool-dispatch path > 1 ms (use a quick assertion in a perf test if
  unsure).
```

**Success gate (D.2):** 5 new tests green; toggle persists; toggle off → no rows; toggle on → rows; version 1.0.31.

#### D.5 — `timeline_search` tool

D.5 is sequenced before D.3/D.4 because it gives the user (and the model) the ability to actually answer "what was I doing yesterday?" using only the data D.2 collects. FSEvents and Vault land later.

**Files MAY add:**
- `OllamaBob/OllamaBob/Tools/TimelineSearchTool.swift` — implements `timeline_search`.
- `OllamaBob/Tests/OllamaBobTests/TimelineSearchToolTests.swift` — ≥ 5 tests.

**Files MAY modify:**
- `OllamaBob/OllamaBob/Agent/ToolRegistry.swift` — register `timeline_search`. Argument schema: `{ "since": "ISO8601 string", "until": "ISO8601 string?", "source": "tool|chat|fsevents?", "kind": "string?", "limit": "integer? default 50" }`. Required: `since`. Approval: `none` (read-only). ≤ 25 LOC.
- `OllamaBob/OllamaBob/Agent/AgentLoopToolDispatch.swift` — `case "timeline_search":` branch. ≤ 6 LOC.
- `OllamaBob/OllamaBob/Personality/BobOperatingRules.swift` — add `timeline_search` to the available-tools table.
- `OllamaBob/OllamaBob/Agent/ApprovalPolicy.swift` — `case "timeline_search": return .none`.

**Files MAY NOT touch:** every other file.

**Tool result format:** plain text, line-per-event, capped at 50 events per call. Each event line: `[ISO8601] <source>/<kind> <conversation-id-prefix> <detail>`. The result must be wrapped in `<untrusted>` so R2 (Phase B) tainting fires correctly — file paths and OCR detail can carry adversarial text.

**Sub-agent dispatch prompt (verbatim):**

```
You are executing Phase D.5 of docs/ACTIVE_EXECUTION_PLAN.md.

Compliance Check-in.

Implement timeline_search per §D.5. Hard rules:

1. The tool is read-only and approval-level .none.
2. The result is wrapped with UntrustedWrapper.wrap(_:source: .timelineSearch). This makes Phase B
   tainting fire when the tool returns content.
3. The tool fails closed when AppSettings.shared.activityTimelineEnabled == false; return a clear
   denied result naming the toggle.
4. The tool MUST cap results at 50 events even if the model passes a larger limit.
5. Date parsing accepts ISO8601 with optional Z suffix; on parse failure return a structured error.
6. Add the tool to ToolRegistry, AgentLoopToolDispatch, ApprovalPolicy, and BobOperatingRules in
   exactly the LOC budgets listed.
7. Tests:
     - testTimelineSearchReturnsRecentEvents
     - testTimelineSearchRespectsLimit
     - testTimelineSearchFailsWhenToggleOff
     - testTimelineSearchWrapsResultUntrusted
     - testTimelineSearchSourceFilterIsHonored
8. Bump to 1.0.32.

STOP TRIGGERS specific to Phase D.5:
- Tool result is not <untrusted>-wrapped.
- Approval policy for timeline_search is anything other than .none.
- The tool can write or mutate any state.
```

**Success gate (D.5):** 5 new tests green; tool registered, untrusted-wrapped, gated by toggle.

(Phases D.3, D.4, D.6, D.7 follow the same pattern. Each ships behind its own Preferences toggle. Each uses Phase B's `UntrustedWrapper.wrap(_:source:)`. Detailed dispatch prompts for D.3, D.4, D.6, D.7 follow the templates above; the supervisor authors them when D.2 and D.5 are landed and observed in real use, since Phase 5 plan flagged "split harder when we get there.")

##### D.3 — FSEvents source

Scope per `archive/PHASE_5_PLAN_2026-04-28.md` §5.3. Path-only events, never bodies. Throttle 1/30s/folder. Per-folder mute.

##### D.4 — Document Vault schema + chunker

Scope per Phase-5 plan §5.4–5.5. Embedding model: **DEFER** until owner answers (Phase-5 question 6 is unanswered). Provisional plan: Apple `NLContextualEmbedding` because zero deps and no model-bundle ship complications. If owner picks bundled MiniLM, add a §S4 Owner-approval gate before D.4 dispatches.

##### D.6 — `search_vault` tool

Read-only, approval `.none`, untrusted-wrapped, gated by `activityVaultEnabled` toggle.

##### D.7 — `summarize_recent_work` tool

Read-only, approval `.none`, untrusted-wrapped, calls into D.5/D.6 internally. The model is not allowed to recurse: enforce a single internal call.

---

### Phase E — Naughty Bob compaction budget

**Why now.** R7 from peer review. Today uncensored mode silently exhausts context. The fix is a *visible* warning the user can see and act on.

**Files MAY add:**
- `OllamaBob/OllamaBob/Services/ContextBudget.swift` — pure function: input = current message stack + model num_ctx; output = approx-token count and percent.
- `OllamaBob/OllamaBob/Views/Desk/UncensoredBudgetBanner.swift` — banner subview.
- `OllamaBob/Tests/OllamaBobTests/ContextBudgetTests.swift` — ≥ 4 tests.

**Files MAY modify:**
- `OllamaBob/OllamaBob/Views/BobsDeskView.swift` — add ≤ 30 LOC: mount the banner above the input row only when `session.conversationUncensoredMode == true && ContextBudget.percent >= 0.85`.

**Files MAY NOT touch:** AgentLoop.swift, ApprovalPolicy.swift, ChatSessionController.swift body. The compaction subsystem stays untouched — uncensored mode does NOT silently fall back, this is a UI-only nudge.

**Required tests:**

1. `testContextBudgetReportsZeroOnEmptyStack`
2. `testContextBudgetCountsAllRoles`
3. `testContextBudgetPercentageCorrectAtKnownNumCtx`
4. `testContextBudgetUsesQwenAbliteratedDefaultNumCtx`

**Sub-agent dispatch prompt:** Standard template; budget approximator may use a simple `text.count / 3.5` heuristic — no tokenizer dependency.

**Success gate (E):** banner visible only at ≥ 85% in uncensored mode; exits to standard mode dismisses banner; version bumped.

---

### Phase F — V9 Native Artifact Workbench

Sub-phases F.1 → F.6 add typed artifact kinds; F.7 wires `present(kind=artifact, type=..., payload=...)` into the existing presentation pipeline.

#### F.1 — ArtifactStore + kinds

**Files MAY add:**
- `OllamaBob/OllamaBob/Models/Artifact.swift` — value type with `kind: ArtifactKind`, `payload: Data`, `id: UUID`, `createdAt: Date`.
- `OllamaBob/OllamaBob/Services/ArtifactStore.swift` — `@MainActor` ObservableObject with in-memory list of recent artifacts (cap 32).
- `OllamaBob/Tests/OllamaBobTests/ArtifactStoreTests.swift` — ≥ 4 tests.

**ArtifactKind cases:** `table`, `checklist`, `diff`, `code`, `fileTree`. Adding a kind is the only way to extend; do not add a free-form `html` case.

**Files MAY NOT touch:** anything outside the three files above and the registration in F.7.

#### F.2–F.6 — Per-kind SwiftUI views

Each F.x sub-phase adds one `OllamaBob/OllamaBob/Views/Artifacts/<Kind>ArtifactView.swift` and one test file. Hard rule: no `WKWebView`, no JS, no AppKit-only HTML rendering. SwiftUI primitives only.

| Sub-phase | View | Payload schema (JSON) |
|---|---|---|
| F.2 | TableArtifactView | `{ "headers": [string], "rows": [[string]] }` |
| F.3 | ChecklistArtifactView | `{ "items": [{"text": string, "done": bool}] }` |
| F.4 | DiffArtifactView | `{ "patch": string }` (unified diff text; reuse `WriteDiff.colorize`) |
| F.5 | CodeArtifactView | `{ "language": string, "code": string }` (no JS execution; static SwiftUI Text with monospaced font) |
| F.6 | FileTreeArtifactView | `{ "root": "string", "entries": [{"path": string, "kind": "file"|"dir", "depth": int}] }` |

Each view: read-only render. Edit/replay is F.7 territory.

#### F.7 — `present(kind=artifact)` integration

**Files MAY modify:**
- `OllamaBob/OllamaBob/Tools/PresentTool.swift` — extend the existing `present` tool to accept `kind=artifact` plus `artifactType` and `payload`. ≤ 50 LOC.
- `OllamaBob/OllamaBob/Services/PresentationService.swift` — route artifact-kind to ArtifactStore. ≤ 30 LOC.
- `OllamaBob/OllamaBob/Views/BobsDeskView.swift` — add ≤ 20 LOC: an inline artifact chip in the transcript that opens the artifact in a side-panel or sheet.

**Files MAY NOT touch:** RichHTMLView, the JS-related WKWebView config, `Tools/PresentTool.swift` `kind=html|url|file` branches.

**Hard rule:** `kind=artifact` MUST go through the same `ApprovalPolicy.check` that `kind=html|url|file` use today. The presentation pipeline does not bypass approvals.

**Required tests:**

1. `testPresentArtifactRoutesToArtifactStore`
2. `testPresentArtifactRejectsInvalidPayload`
3. `testPresentArtifactKindRespectsApprovalPolicy`

**Sub-agent dispatch prompt:** standard template plus emphasis on "no JS, no WKWebView, no HTML rendering anywhere in this phase." Bump to 1.0.33+ on F.7.

---

### Phase G — Privacy Ledger Aggregate View

**Files MAY add:**
- `OllamaBob/OllamaBob/Views/PrivacyLedgerAggregateView.swift` — new view.
- `OllamaBob/Tests/OllamaBobTests/PrivacyLedgerAggregateTests.swift`.

**Files MAY modify:**
- `OllamaBob/OllamaBob/Persistence/Database.swift` — add `func aggregateExecutionLog(since: Date, until: Date) throws -> [LedgerAggregateRow]` returning rows grouped by tool name with counts and approval distribution.
- `OllamaBob/OllamaBob/OllamaBobApp.swift` — register the new window `Window("Privacy Activity", id: "privacy-aggregate") { PrivacyLedgerAggregateView() }`.

**Files MAY NOT touch:** the existing single-execution Privacy Ledger view (`PrivacyLedgerView.swift`).

**Required tests:** ≥ 4. Cover: aggregate counts correct, time-range filter, empty-state, ledger-disabled-state.

---

### Phase H — Multi-model orchestration

**Why.** Latency. Small fast model picks tools and writes short replies; large model only on hard reasoning.

**Files MAY add:**
- `OllamaBob/OllamaBob/Agent/ModelRouter.swift` — pure function: `route(messages: [Message], lastUserText: String) -> (model: String, reason: String)`.
- `OllamaBob/Tests/OllamaBobTests/ModelRouterTests.swift` — ≥ 8 tests.

**Files MAY modify:**
- `OllamaBob/OllamaBob/Agent/AgentLoop.swift` — ≤ 60 LOC. Replace the single-model selection with a router call. The router reads `AppSettings.shared.fastModelEnabled` (default false) and `AppSettings.shared.fastModelName` (default `qwen3:4b` or whatever owner approves — provisional default; OWNER MUST APPROVE before dispatch).
- `OllamaBob/OllamaBob/Models/AppSettings.swift` — two new keys.
- `OllamaBob/OllamaBob/Views/PreferencesView.swift` — toggle + model picker. ≤ 50 LOC.

**Owner-approval gate (S4-style):** the default fast-model name requires explicit owner answer before this phase dispatches. STOP and ask if not provided.

**Routing heuristic v1:**

- If the last user message is < 60 chars and contains no code block → fast.
- If the last user message contains `?` and the conversation has < 4 turns → fast.
- If a tool call result was just delivered and was successful → fast (for the tool-call follow-up turn).
- Else → standard.

These heuristics are testable as pure functions on a `RoutingInput` struct.

**Required tests:** 8 covering each branch + fallback when toggle off (always uses standard model).

---

### Phase I — Tier 4 Quick Wins

#### I.1 — Finder Quick Action (`NSServices`)

**Files MAY add:**
- `OllamaBob/OllamaBob/Services/FinderServiceProvider.swift` — `NSServicesProvider` exposing `askBobAboutFile(_:userData:error:)` that reads the file path arguments, builds a `read_file`-style untrusted-wrapped prompt, enqueues via `DeskPromptInbox`, and opens the chat window.
- `OllamaBob/Tests/OllamaBobTests/FinderServiceProviderTests.swift` — ≥ 3 tests.

**Files MAY modify:**
- `OllamaBob/build.sh` — add the `NSServices` block to the generated Info.plist with the service name "Ask Bob about this file…" bound to `askBobAboutFile`. ≤ 30 LOC.
- `OllamaBob/OllamaBob/OllamaBobApp.swift` — register the provider on launch (`NSApp.servicesProvider = FinderServiceProvider.shared`). ≤ 5 LOC.

**Files MAY NOT touch:** any tool, any existing view.

**Hard rule:** the file's bytes are never read until the user is in the chat window and explicitly sends; only the path comes from Finder. The file body, if read, is `<untrusted>`-wrapped (because the file content may have been authored by a third party).

#### I.2 — App Scout tool

**Files MAY add:**
- `OllamaBob/OllamaBob/Tools/AppScoutTool.swift` — read-only, approval `.none`. Returns capability inventory: presence of common CLIs (`ffmpeg`, `yt-dlp`, `sips`, `imagemagick`, `git`, `swift`, etc.) and presence of common GUI apps via `NSWorkspace.urlForApplication(withBundleIdentifier:)`.
- `OllamaBob/Tests/OllamaBobTests/AppScoutToolTests.swift` — ≥ 4 tests.

**Files MAY modify:**
- ToolRegistry.swift, AgentLoopToolDispatch.swift, ApprovalPolicy.swift, BobOperatingRules.swift — register the tool.

**Hard rule:** the inventory list is FIXED in code, not user-configurable, to avoid arbitrary path probes. ≈ 12 CLIs and ≈ 8 apps.

#### I.3 — Avatar State as Control Surface

**Files MAY modify:**
- `OllamaBob/OllamaBob/Views/BobsDeskView.swift` — ≤ 30 LOC: add a `tap`/`option-tap` gesture on the portrait that surfaces a small mode-swap menu (focus mode, walkie-talkie, dev mode, uncensored). Modifier-tap shortcut bindings. The menu items toggle the existing `AppSettings` flags through the same code paths Preferences uses.

**Files MAY NOT touch:** ChatSessionController, AgentLoop, ToolRegistry. This is pure UI sugar over existing settings.

**Required tests:** ≥ 3 view-model unit tests (no UI snapshot).

#### I.4 — Screen-to-Action Debugger

**Files MAY add:**
- `OllamaBob/OllamaBob/Skills/ScreenToActionSkill.swift` — declarative skill (V4 Skill Capsule) over existing tools: `screen_ocr` → `current_context` → suggest a `shell` invocation behind approval.
- `OllamaBob/Tests/OllamaBobTests/ScreenToActionSkillTests.swift`.

**Hard rule:** this is a Skill Capsule (V4 surface), not a new tool. It MUST go through `run_skill` → `ToolRuntime` → `ApprovalPolicy`. No bypass.

---

## 5. Sub-agent dispatch template (verbatim — use for any phase whose dispatch prompt above is shorter than this template)

```
You are a Sonnet executor for OllamaBob phase {N} ({title}). You are NOT the supervisor. You do not
commit, merge, push, or tag.

Read in order:
1. /Users/zack/ollamaBob/docs/ACTIVE_EXECUTION_PLAN.md (this file)
2. /Users/zack/ollamaBob/AGENTS.md
3. /Users/zack/ollamaBob/CLAUDE.md
4. /Users/zack/ollamaBob/docs/CURRENT_HANDOFF.md
5. The §4 entry for phase {N} above.

You are working on branch feature/{slug}-{date} which is already created and checked out.

Step 1: Compose the COMPLIANCE CHECK-IN block per §0.4 of the plan and STOP for one beat. Re-read it.
        If anything is off, fix the check-in before proceeding.

Step 2: TDD. For every new behavior, the first artifact is a failing test. Confirm RED, then implement,
        then confirm GREEN. Do NOT batch tests.

Step 3: Implement the scope-IN bullets in the order they appear in §4. Stay inside the LOC budget.

Step 4: Bump version per §0.6 if user-visible behavior changed. Update all six version files.

Step 5: Run the success gate (§0.6).

Step 6: Compose the EXECUTOR REPORT (§0.7). Return only that report. Do not start phase {N+1}.

If a §0.5 universal STOP or a phase-specific STOP fires, return a STOP report with the trigger ID
and what you observed. Do not attempt to work around it.

Constraints you carry into every phase:
- One coding session, one phase. No re-dispatch.
- No git commit, merge, tag, or push under any circumstance.
- No `--no-verify`, `--no-edit`, `commit.gpgsign=false` overrides except where this plan explicitly
  authorizes them.
- No new SPM dependencies without an explicit owner-approval gate triggered first.
- No streaming, no /v1/chat/completions, no MCP, no JS in WKWebView, no Python/Electron/Docker.
- No weakening or bypassing ApprovalPolicy / PathPolicy / forbidden-shell floors.
- BobsDeskView.swift, AgentLoop.swift, PreferencesView.swift LOC budgets per the §3 table are hard.
- Read tools may run silently. Side-effecting tools require approval. Always preserve.
```

---

## 6. Resumption rules

If a session is interrupted mid-phase:

1. The supervisor verifies the feature branch is intact.
2. If the executor produced a Compliance Check-in, retain it. The fresh executor must produce its own check-in matching the plan, then continue.
3. If a partial diff exists, the new executor reads the diff, decides whether the partial work is salvageable, and either continues or reverts (`git checkout -- <path>`) before continuing. The new executor reports the salvage decision in its report.
4. **Never carry a phase across more than two executor sessions.** If a third session is required, the supervisor splits the phase into smaller sub-phases and updates this document before re-dispatching.

---

## 7. Owner approval checkpoints

| Before | What owner approves |
|---|---|
| Phase A.3 (Kimi merge) | Confirm Kimi K1 fix matches owner expectations and conflict-resolution strategy for `AppConfig.swift`. |
| Phase D.4 (Vault chunker) | Pick embedding model: Apple `NLContextualEmbedding` (zero-dep, recommended) vs. bundled CoreML MiniLM (better quality, larger bundle). Phase 5 plan question 6. |
| Phase H | Pick fast-model default name. |
| Any phase that wants a new SPM dependency | Approve the dependency before dispatch. |
| Any phase whose Compliance Check-in disagrees with the plan | Approve the corrected check-in. |

The owner can decline a phase, reorder Tier 4, or pause execution between any two phases. Tier 1 and 2 phases are sequential and cannot be reordered.

---

## 8. What is explicitly NOT in this plan

- JS in `RichHTMLView`. Closed.
- MCP / Python / Electron / Docker runtime. Closed.
- Web Companion / browser control. Out of scope for this plan; revisit after V3 ships.
- A plugin SDK other than Skill Capsules. Closed.
- Streaming (`stream: true`). Closed.
- `/v1/chat/completions` migration. Closed.
- Removing `ChatPanel.swift` (open question, not blocking).
- Anything in `archive/` not explicitly referenced by a §4 phase.

---

## 9. Notes for whoever resumes this plan

- The plan is a single source of truth. If `docs/CURRENT_HANDOFF.md` and this file disagree, this file wins until the last phase is merged, after which the supervisor archives this file and refreshes the handoff.
- Phase numbering does not correspond to peer-review phase numbering. The mapping is in `archive/PEER_REVIEW_TODO_2026-04-28.md` for posterity.
- The Compliance Check-in is the single most important discipline. Every failed sub-agent dispatch in the previous session was caught (or would have been caught) at check-in time. Do not skip it.
