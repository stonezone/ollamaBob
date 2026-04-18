# Archive

Historical artifacts from earlier phases of OllamaBob. Preserved for reference
but no longer part of the active project. Everything here is still useful as a
"why did we decide X?" reference — it's just not day-to-day reading.

## Contents

| Path | What it is | Phase | Still relevant for |
|------|-----------|-------|--------------------|
| `OLAMMABOB_PROMPT.md` | Original V1 kickoff prompt handed to the first implementation agent. | V1 | Historical context only. **References the deprecated `/v1/chat/completions` endpoint — the codebase uses `/api/chat`.** See CLAUDE.md errata. |
| `phase0/` | Pre-implementation investigations — `num_ctx` benchmarks (`invA*`), tool-call wire-format samples (`invB*`), jq bundle viability check (`invC*`). | Pre-V1 (2026-04) | Revisit before revisiting any of the decisions those benchmarks produced (e.g. `num_ctx: 8192` default, no-bundled-jq stance). |
| `PHASE0_RESULTS.md` | Narrative write-up of the phase-0 investigation results. Companion to `phase0/`. | Pre-V1 | Same as above. |
| `OLLAMABOB_V2_PLAN_DRAFT.md` | Earlier V2 scope draft, kept for context. **Superseded by `docs/OLLAMABOB_V2_PLAN_FINAL.md`.** | V2 planning | Delta-reading against `_FINAL` if you want the backstory of the cut items (`sqlite-vec`, etc.). |
| `OLLAMA_CLAUDE_V2.5_plan.md` | Autonomous orchestration plan used to ship V2.5 "Make Bob Sing". | V2.5 | Reference only — V2.5 is shipped. |
| `OLLAMABOB_V2.9_PHASE_A_PLAN.md` | Handoff plan that shipped V2.9 Phase A (OCR / speak / weather / units / sips / yt-dlp). | V2.9 Phase A | Copy its structure if you're writing a new Codex handoff — it's the canonical "how we hand off bounded work" template. |
| `future_features/` | Parked feature ideas. Currently just `generate_images.txt` (prompts for future image-gen tool). | Ongoing | Reactivate when a feature's turn comes up. |

## Why these are archived, not deleted

Each of these shaped a real decision the project is still living with. Keeping
them in the repo means the reasoning behind the decision stays recoverable
(via git history and file content) even after the originating doc is no longer
relevant day-to-day. Binaries that were part of those investigations are
gitignored via `archive/**/*.app/` patterns in the root `.gitignore`.
