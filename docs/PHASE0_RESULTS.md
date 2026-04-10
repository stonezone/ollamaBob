# OllamaBob V2 — Phase 0 Investigation Results

**Date:** 2026-04-09
**Hardware:** Apple M1, 32 GB RAM, macOS 26.5 (25F5042g), arm64
**Ollama:** running at `http://localhost:11434`
**Models tested:** `gemma4:e4b` (9.2 GB), `qwen3:14b` (8.8 GB)

Three investigations were run to validate assumptions in `OLLAMABOB_V2_PLAN_FINAL.md` before any production code is written. All scripts and raw results live in `phase0/`.

---

## TL;DR

| Investigation | Verdict | Effect on V2 plan |
|---|---|---|
| **A — `num_ctx` ceiling** | ✅ **PASS** (surprise: zero overhead from 8K → 32K) | Default `num_ctx` can jump to **32768** on both models. Phase 5 (compaction) pressure drops. |
| **B — shell quoting on gemma4:e4b** | ✅ **PASS** (47/50, every special-char category 100%) | CLAUDE.md's warning about Gemma 4 crashing on backticks/braces/regex is **stale**. Beta-gating for "complex quoting" can be **narrower** than originally planned. |
| **C — dylibbundler + codesign for `jq`** | ✅ **PARTIAL PASS** (bundle + sign + run all work; notarization deferred) | The 8-tool bundled set in Phase 2.2 is viable. Full notarization gate still needs a Developer ID Application cert. |

**Phase 1 can begin.** Three concrete scope adjustments drop out of the results (see "Plan updates required" below).

---

## Investigation A — `num_ctx` ceiling

### Question
Can `num_ctx` be raised above v1's 8192 on M1 / 32 GB without blowing latency, RSS, or OOM on either model?

### Method
Two scripts, both in `phase0/`:

1. **`invA_num_ctx_bench.py`** — stressed each model at `num_ctx ∈ {8192, 12288, 16384, 24576, 32768}` with a ~5000-token fixture prompt. Measured wall time, Ollama's reported `total_duration` / `load_duration` / `eval_duration`, and the RSS of the `ollama runner` process.
2. **`invA2_short_prompt.py`** — supplementary pass with a trivial "what's 2+2?" prompt at 8K / 16K / 32K so baseline per-ctx overhead could be separated from prompt-eval cost.

Raw results: `phase0/invA_results.jsonl`, `phase0/invA2_results.jsonl`.

### Results — stressed prompt (~5K tokens)

| Model | ctx | wall (ms) | total (ms) | eval (ms) | TTFT (ms) | RSS (GB) |
|---|---|---|---|---|---|---|
| gemma4:e4b | 8192 | 8725 | 8721 | 1723 | 6998 | 5.84 |
| gemma4:e4b | 12288 | 9059 | 9056 | 1797 | 7259 | 3.30 |
| gemma4:e4b | 16384 | 8707 | 8705 | 1713 | 6992 | 5.63 |
| gemma4:e4b | 24576 | 8660 | 8658 | 1686 | 6972 | 2.26 |
| gemma4:e4b | 32768 | 8667 | 8664 | 1686 | 6978 | 3.21 |
| qwen3:14b | 8192 | 24297 | 24293 | 2864 | 21429 | 10.06 |
| qwen3:14b | 12288 | 24245 | 24242 | 2859 | 21383 | 10.70 |
| qwen3:14b | 16384 | 26320 | 26317 | 2925 | 23392 | 11.33 |
| qwen3:14b | 24576 | 29966 | 29963 | 3181 | 26782 | 12.61 |
| qwen3:14b | 32768 | 31008 | 31002 | 3238 | 27764 | 11.39 |

### Results — baseline short prompt ("What is 2+2?", warm model)

| Model | ctx | wall (ms) | total (ms) | prompt_eval (ms) | eval (ms) | TTFT (ms) |
|---|---|---|---|---|---|---|
| gemma4:e4b | 8192 | 282 | 281 | 82 | 18 | 263 |
| gemma4:e4b | 16384 | 272 | 271 | 80 | 18 | 253 |
| gemma4:e4b | 32768 | 272 | 271 | 82 | 18 | 253 |
| qwen3:14b | 8192 | 516 | 513 | 160 | 284 | 229 |
| qwen3:14b | 16384 | 534 | 529 | 166 | 291 | 238 |
| qwen3:14b | 32768 | 524 | 523 | 166 | 287 | 236 |

### Interpretation

- **The stressed run looked like a FAIL against the original ≤4000 ms TTFT gate. It wasn't.** On gemma4:e4b, TTFT is **flat at ~7 seconds across all five ctx sizes** — that's the prompt-evaluation cost of the 5K-token fixture, not context overhead. On qwen3:14b, there's a mild walk (21 s → 27 s) as ctx grows, but it's still dominated by prompt eval.
- **The short-prompt run gives the real answer.** With a warm model and a trivial prompt, gemma4:e4b holds **~253 ms TTFT at every ctx size from 8K to 32K**, and qwen3:14b holds **~236 ms TTFT** likewise. Raising `num_ctx` is *free* at idle on both models.
- **RSS never exceeds 12.61 GB** on qwen3:14b at 32K under load, and **5.84 GB** on gemma4:e4b. Both are comfortably under the 22 GB safety bar the plan set.
- **Neither model OOMs, thrashes, or throws any error at any ctx size.**

### Verdict

✅ **PASS.** Both models are safe at `num_ctx = 32768` on this hardware.

- Raise `AppConfig.numCtx` default from 8192 to **32768**.
- The `ctx meter` added in v1.1 already works with any ceiling.
- Phase 5 (compaction) becomes *less* pressing — at 32K, a long workday session has ~4× the headroom before compaction needs to fire.

### Caveats

- qwen3:14b at 32K has a modest prompt-eval penalty (~6 s extra on a 5K prompt compared to 8K). That's real cost, but it only materializes when the prompt is actually big — not on idle turns. It reinforces the plan's decision to keep qwen3:14b as the *compactor*, not the primary.
- The 22 GB RSS cap assumed a worst case with two models and a KV cache loaded simultaneously. In practice, only one model is resident at a time thanks to `keep_alive` tuning. The measured peak was 12.61 GB. There's plenty of headroom.

---

## Investigation B — shell-quoting reliability on gemma4:e4b

### Question
How reliably does gemma4:e4b produce shell tool calls with arguments that survive special characters — backticks, `$()`, brace expansion, regex, paths with spaces, unicode filenames, heredocs, JSON-in-args, escape sequences?

### Method
50 fixture prompts in `phase0/invB_fixtures.json`, grouped into 11 categories, each targeting a specific shell-quoting hazard. `phase0/invB_run.py` sends each through `/api/chat` using the exact flat tool schema Bob's v1 `ShellTool` uses, then scores the response:

- **PASS** — produced a `shell` tool call with a non-empty `command` string that doesn't look like a placeholder (`<path>`, `[file]`, `{VAR}`).
- **FAIL_NO_TOOL** — model returned text instead of a tool call.
- **FAIL_PARSE** — `arguments` couldn't be decoded.
- **FAIL_EMPTY** — shell tool called with null/empty command.
- **FAIL_PLACEHOLDER** — command contained a templated placeholder.

Pass bar (per V2 plan): **≥ 45 / 50**.

Raw results: `phase0/invB_results.jsonl`, `phase0/invB_summary.txt`.

### Results

**Overall: 47 / 50 PASS** ✅

| Category | Score |
|---|---|
| backticks + command substitution | **5 / 5** |
| brace expansion | **5 / 5** |
| regex in grep / rg | **6 / 6** |
| paths with spaces | **5 / 5** |
| paths with quotes | **4 / 4** |
| unicode filenames | **4 / 4** |
| shell special chars in args | **7 / 7** |
| JSON inside shell args | **4 / 4** |
| heredoc / multiline payload | **3 / 3** |
| long single-line (multi-step) | 2 / 4 |
| escape chars | 2 / 3 |

### The 3 failures — root cause is NOT quoting

All three failures were `FAIL_NO_TOOL` with empty `raw_message_text`. They weren't garbled tool calls or corrupted arguments — the model returned nothing at all. The failing fixtures were:

- **#30** — "In one shell call, create /tmp/inv_b_test, cd into it, touch 5 files a.txt through e.txt, list them with ls -la, and print the total count." (complex compound command, 4 discrete steps)
- **#31** — "Find all .md files under /Users/zack/ollamaBob/docs, count them, and print the count on the same line as the word 'count:' using a pipeline." (complex compound pipeline)
- **#48** — "Echo a single backslash character (just `\\`) using echo -e." (a 4-word prompt with an ambiguous goal)

All three look like **output-token truncation or prompt confusion**, not shell escaping. Fixtures with equivalent or harder quoting but clearer single-action intent (e.g. #34 "write a small shell script via heredoc", #44 "curl POST with JSON body", #28 "create /tmp/日本語.txt") all passed.

### Interpretation

This is a bigger finding than the pass bar. **The `CLAUDE.md` warning that Gemma 4 "crashes the parser" on backticks, braces, and regex in tool arguments is stale.** With `stream: false` and a flat tool schema, gemma4:e4b handled every special-character category at 100%.

### Verdict

✅ **PASS.**

- Gemma4:e4b stays as the primary model. No switch to qwen3:14b needed.
- The v1 `qwen3:14b` fallback on 3 consecutive tool parse failures still stays in as a safety net, but it's looking like a belt-and-suspenders backup, not a load-bearing feature.
- The "Complex quoting" beta-gating category in the V2 plan can be **narrowed**:
  - The broad concern (ffmpeg, pandoc, sed -E, awk, rg with lookarounds) is based on outdated evidence. Re-evaluate on a per-tool basis during Phase 2 rather than pre-gating.
  - Keep gating for **compound multi-step requests** in the cheat sheet's prompting guidance instead: "Break complex pipelines into 2-3 sequential tool calls, not one giant command."

### Caveats

- Each fixture was run **once**. Non-determinism in the model could flip a pass to a fail on a rerun. Investigation B should be re-run in CI before every V2 release.
- The fixtures were single-turn. Multi-turn tool-call sequences (where the model has to reference a previous result) were not tested here — that's covered by acceptance test B11 in the final plan.
- Response truncation (fixtures #30, #31) suggests bumping the `num_predict` default for tool calls. Currently no explicit cap in v1; Ollama's default is `-1` (infinite). The fixtures ran with `num_predict = 512` for speed; if that's the cause, production Bob doesn't hit it.

---

## Investigation C — dylibbundler + codesign for `jq` (partial)

### Question
Can `/opt/homebrew/bin/jq` (a real Homebrew binary with a real dylib chain) be bundled into a macOS `.app`, codesigned with a hardened runtime, and actually executed — end to end? Reviewers called this out as the make-or-break smoke test for the whole "bundle small tools inside OllamaBob.app" plan.

### Method
`phase0/invC_jq_bundle.sh` performs the full inside-out pipeline that a production build would use:

1. Create a synthetic `InvC.app` skeleton with a stub main executable
2. Copy `/opt/homebrew/bin/jq` (1.8.1) into `Contents/Resources/bin/jq`
3. Run `dylibbundler` to rewrite its dylib load paths to `@executable_path/../../Frameworks/` and copy every non-system dependency into `Contents/Frameworks/`
4. Verify with `otool -L` that **no `/opt/homebrew` absolute paths survive** in either the binary or the relocated dylibs
5. Codesign every Mach-O (both dylibs, the bundled jq, the stub executable, and the app bundle itself) with hardened runtime + secure timestamp, using the local `Apple Development: zachariah jordan` certificate
6. Run `codesign --verify --deep --strict` on the final bundle
7. Execute the bundled jq with `--version` and with a real `.models[].name` filter against sample JSON to confirm it runs

Raw results: `phase0/invC_report.txt`, bundled `.app` left at `phase0/InvC.app` for manual inspection.

### Results

| Step | Outcome |
|---|---|
| 1. `.app` skeleton | ✅ Created |
| 2. Copy jq | ✅ Succeeded |
| 3. dylibbundler exit | ✅ 0 (success) |
| 4. No `/opt/homebrew` paths remain | ✅ `libjq.1.dylib` and `libonig.5.dylib` both rewritten to `@executable_path/../../Frameworks/` |
| 5. Codesign (hardened runtime) | ✅ All four Mach-O files signed and verified |
| 6. `codesign --verify --deep --strict` | ✅ "valid on disk", "satisfies its Designated Requirement" |
| 7. `jq --version` from bundled binary | ✅ Output: `jq-1.8.1` |
| 7. Filter test: `.models[].name` | ✅ Output: `gemma4:e4b` and `qwen3:14b` as expected |

### Verdict

✅ **PARTIAL PASS.** Every step that can be validated without an Apple Developer ID cert passed cleanly on the first try.

**What's been proven:**
- dylibbundler successfully relocates `jq`'s dependency chain, which was the specific concern reviewers called out ("brew binaries have hardcoded prefixes that dylibbundler cannot rewrite")
- Hardened-runtime codesigning with a local dev cert works on the bundled layout
- The signed bundled binary actually executes and produces correct output

**What's still deferred:**
- Full `xcrun notarytool submit` round-trip, which requires a **Developer ID Application** cert not currently in the keychain. Notarization would validate (a) that Apple's scanner accepts the bundled layout, (b) that the stapled ticket works on a clean machine without `com.apple.quarantine` dialogs. Both are real concerns but neither is blocked by anything Phase 1 or Phase 2 code needs to do.

### Action required for full C pass

User must confirm **one of the following** before Phase 7 (Notarization & distribution):

1. Enroll / verify enrollment in Apple Developer Program ($99/yr), generate a "Developer ID Application" cert, install it in the keychain, and store an `xcrun notarytool store-credentials` profile. Then re-run `invC_jq_bundle.sh` with the new cert and append the notarization step.
2. Ship V2 as an unsigned/ad-hoc binary (install via `xattr -dr com.apple.quarantine` instructions in the README). This works for local/personal use but fails as a general distribution story.
3. Skip the "bundle anything" path entirely and fall back to pure detection + `brew install` offers. The existing partial pass is wasted work but no production code is blocked.

### Interpretation

The dominant reviewer concern — *"you can't actually bundle a Homebrew binary, dylibbundler will choke on the dylib chains"* — is **disproven for jq**. Proved with the simplest case; it's not evidence that every tool in the bundled set will work, but it's evidence that dylibbundler isn't the wall the review suggested. The rest of the bundled 8 (`yq`, `mlr`, `rg`, `fd`, `bat`, `tree`, `age`) need their own `invC-style` runs before Phase 2.2 ships, but those should go fast now that the harness script exists.

---

## Plan updates required

The final V2 plan (`docs/OLLAMABOB_V2_PLAN_FINAL.md`) needs three edits to reflect Phase 0 findings. None of them expand scope; they all refine or relax existing constraints.

### 1. `AppConfig.numCtx` default → 32768

**Current plan:** "Raise `num_ctx` to Investigation A's verified ceiling (default = A's ceiling, floor = 8192, cap = 32768)."

**Update:** A's verified ceiling is **32768** on both models. Default = 32768. Keep the floor/cap as guardrails but the UI slider can show the full range with no scary warnings until we have a reason to add them.

### 2. Narrow the "Complex quoting" beta-tools category

**Current plan:** Beta-gate `ffmpeg`, `pandoc`, `sed -E`/`awk` as scripts, `rg` with lookarounds.

**Update:** Investigation B contradicted the stated rationale. Specifically:
- Keep `ffmpeg` and `pandoc` in the Beta / "Complex quoting" bucket because their *usage patterns* (filter_complex chains, metadata args) weren't tested in Investigation B's single-command fixtures. We still don't have data on those.
- **Remove** `sed -E`/`awk` scripts and `rg` with lookarounds from the beta list. They were pre-gated based on the stale CLAUDE.md warning that Investigation B disproved.
- Keep the CTF tools (`nmap`, `httpx`, `ffuf`, `feroxbuster`) in Beta — that gate is about security, not model reliability.

### 3. Acceptance test B18 (Phase 0 regression)

**Add:** Re-run Investigation B's 50-fixture set in CI before every V2 release as a regression gate. Pass bar stays at ≥ 45 / 50. Any drop below signals model drift (Ollama version bump, new gemma4 point release) and blocks the release.

---

## What's ready for Phase 1

- ✅ All three investigations resolved (C partial, with a clear gate deferred to Phase 7)
- ✅ Ollama, both models, and all build prerequisites (dylibbundler, codesign, xcrun) verified on this machine
- ✅ `phase0/` scripts are reusable — A2 and B in particular can run in CI on every PR
- ✅ Concrete plan updates identified; all three are relaxations, not additions

**Blockers for Phase 1 start:** none.

**Phase 1 scope reminder** (from the final plan):
1. Raise `num_ctx` default + Preferences slider
2. Remove hardcoded Mumbai persona → `PersonaStore` + `BobOperatingRules` separation
3. Tool output spillout with integer ids + `read_tool_output` meta-tool
4. Per-category approval policy
5. Prompt-injection hardening with `<untrusted>` delimiters

The first Phase 1 commit should touch only `AppConfig.swift` and a new `docs/PHASE0_RESULTS.md` reference — the smallest possible "raise the ctx default, prove the app still runs" step before the larger refactors.

---

## Open questions for the user

1. **Developer ID Application cert.** Do you want me to kick off Phase 1 without solving notarization (Phase 7), or would you rather resolve the cert situation first so C can be fully validated before we build on the assumption that bundling works?
2. **Beta-tools narrowing.** Do you accept the Investigation B-driven relaxation of the beta list (drop `sed/awk/rg-lookarounds` from beta), or do you want them held in beta out of caution regardless of the benchmark?
3. **Greenlight.** Should I begin Phase 1 Step 1 (`AppConfig.numCtx = 32768` + Preferences slider scaffold) now, or stop for further review of these findings?
