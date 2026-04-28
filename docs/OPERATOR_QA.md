# OllamaBob Operator QA Notes

**Date:** 2026-04-27

## Core Manual Checks

### Repo / Docs Handoff

1. `git status --short --branch` is clean on `main`.
2. Start new work from:
   - `AGENTS.md`
   - `docs/CURRENT_HANDOFF.md`
   - `CLAUDE.md`
3. Confirm old plans and completed handoffs are under `archive/`, not mixed into active `docs/`.
4. Confirm Preferences -> Help -> Learn more points at current docs and `archive/`.
5. Confirm every user-visible app change bumped the version consistently in `AppConfig.swift`, `build.sh`, `README.md`, `CLAUDE.md`, `AGENTS.md`, and `docs/CURRENT_HANDOFF.md`.

### Claude OS / Codex OS RAG

1. Confirm Claude OS is reachable at `http://localhost:8051/health`.
2. Confirm project `ollamaBob` exists for `/Users/zack/ollamaBob`.
3. Confirm these KBs exist and are searchable with filter `ollamaBob-`:
   - `ollamaBob-project_memories`
   - `ollamaBob-project_profile`
   - `ollamaBob-project_index`
   - `ollamaBob-knowledge_docs`
4. Before non-trivial code work, search Claude OS for relevant decisions and code-index context.
5. After code or active-doc changes, update project memory/docs/profile and refresh the project index when source or tests changed.

### Rich Presentation

1. `present(kind=html)` opens Bob's rich view window.
2. Clicked links inside the rich view open externally in the default browser.
3. The rich view stays on the original page after a clicked link.
4. `present(kind=url)` opens the default browser, not an in-app window.
5. `present(kind=file)` opens the file in the default macOS app.
6. Turning rich presentation off removes the `present` tool from Bob and hides transcript artifact chips.

### Naughty Bob v1

1. Preferences -> Models -> `Enable Uncensored Mode` is on.
2. The active conversation has the `UNCENSORED` pill enabled.
3. If the uncensored model is missing, Bob shows a banner with the exact `ollama pull ...` command.
4. In uncensored mode:
   - tools are off
   - compaction is off
   - fallback to the normal model stack is not allowed

### Tools

1. Preferences -> Tools shows the full built-in catalog. Verify expected categories: Files, Shell, Git, Web, Mail, Phone, Presentation, Media, Utility, YouTube, Clipboard, Automation, Memory.
2. `youtube_search` and `youtube_download` require `yt-dlp` on PATH. If missing, Bob returns "yt-dlp not found on PATH. Install with: brew install yt-dlp".
3. `phone_call`, `phone_hangup`, `phone_status` only appear when Jarvis phone is enabled in Preferences and both `JARVIS_API_KEY` and `OPERATOR_API_SECRET` are configured.
4. `web_search` only appears when `BRAVE_API_KEY` is configured.
5. Read-only tools (green dot) should run silently. Write/ASK tools (orange dot) should show a modal approval dialog.
6. Click a built-in tool permission badge and verify it cycles through `Auto`, `Ask`, and `Deny`.
7. Verify an `Auto` override does not bypass path policy or forbidden shell-command blocks; sensitive paths should still require approval or be denied.
8. In Tool Activity, "Tool execution allowed" means Bob's runtime policy/user approval allowed the tool call. It is separate from macOS Automation permissions.

### Apple Mail

1. Preferences -> Tools -> Mac App Permissions -> Mail should show `granted` after a successful check. This proves the app can send Apple Events to Mail; it is separate from Bob's Auto / Ask / Deny tool policy.
2. Ask Bob "do I have unread mail?".
3. Expected: Bob uses `mail_check`, shows a native approval dialog, and returns message metadata only: received date, read state, sender, and subject.
4. Ask Bob "any mail from <sender>?".
5. Expected: Bob uses `mail_check` with a query instead of generic `applescript`.
6. Bob should not read message bodies, send mail, delete mail, archive mail, or mark messages read through `mail_check`.
7. Ask Bob "read my unread mail and tell me what needs attention".
8. Expected: Bob uses `mail_triage`, shows a native approval dialog, and returns a short attention summary based on truncated previews.
9. `mail_triage` may read short previews, but it should not send mail, delete mail, archive mail, or mark messages read.
10. If the model produces an empty final answer after a mail tool succeeds, Bob should still show a visible fallback summary instead of leaving only the earlier "one moment" bubble.
11. If macOS returns a Mail Automation denial, Bob should tell the user to open Preferences -> Tools -> Mac App Permissions and grant Mail.

### Authorized Music MP3 Workflow

1. Ask Bob for an album you own on CD, using artist and album name.
2. Bob should resolve album ambiguity before downloading, especially when the requested phrase is a song title rather than an album title.
3. Bob should gather an official or reliable track list and create an output folder shaped like `~/Music/Bob/<Artist>_<Album>` for newly-created music folders.
4. Bob should use `youtube_search` per track, auto-pick a high-confidence title/duration match, and ask you to choose only when candidates are genuinely ambiguous.
5. Bob should avoid playlists, full-album uploads, lyric videos, covers, live versions, and remixes unless explicitly selected or no clean studio track is available.
6. Bob should continue through the album after each successful track instead of stopping after one download.
7. If one full-album MP3 is explicitly requested, Bob should find a single full-album video, verify the runtime is close to the album runtime, and save one file named like `<Artist>_<Album>`.
8. If a full-album upload split is explicitly requested, Bob should prefer reliable chapters/timestamps/track-time metadata and use silence detection only as a fallback check.
9. After confirmation and modal approval, `youtube_download` should save MP3 files with clean numbered filenames.
10. For "get N different songs by this artist" requests, Bob should pick distinct popular studio tracks and continue the whole batch without asking after each song.
11. For a pasted song list, Bob should preserve list order, use durations if provided, and continue through every listed item unless a track is ambiguous or denied.
12. If Bob tries to end a batch turn with status-only text such as "Next up is...", the agent loop should continue internally and call the next tool instead of stopping.
13. If asked what is missing from the output folder, Bob should use `list_directory` or quote the folder path correctly, then report downloaded/missing/extra files without asking which requested track is next.

### Local Audio Conversion

1. Give Bob a folder containing `.flac` files and ask him to convert the folder to MP3.
2. Bob should inspect the folder, create/use an output folder such as `MP3`, and use `ffmpeg` locally.
3. Bob should convert every `.flac` in the batch without asking after each file.
4. Bob should preserve base filenames and avoid overwriting existing MP3s unless explicitly asked.
5. Final status should include converted count, skipped existing files, failed files, and output folder.

### Jarvis Phone

1. Preferences -> Tools -> `Enable Jarvis phone service` is on.
2. Both secure fields are filled:
   - `Jarvis API key`
   - `Operator secret`
3. `Test connection` returns healthy reachability.
4. Ask Bob to place a call:
   - expected: approval modal for `phone_call`
   - expected: if the call should reference current work, the approval modal includes a concise `Context:` preview from the recent OllamaBob session plus earlier-work highlights when older same-day work would otherwise fall out of the tail
   - after approval: either a returned `callSid` or a precise auth failure
5. If the daemon returns `401`:
   - capital-`U` `Unauthorized` means the operator secret failed
   - lowercase `unauthorized` means the Jarvis API key failed

### Jarvis Call Prompt Policy

When checking Bob's actual behavior, verify these prompt/policy rules:

1. If the user does not specify a caller persona, Bob should place the call as `bob`.
2. Supported caller identities are exactly:
   - `bob`
   - `buddy`
   - `zack`
   - `glennel`
   - `glennel_naggy`
3. If the user asks for an unsupported caller identity, Bob should ask for clarification instead of silently replacing it.
4. `jarvis` is not a daemon-side caller identity; Bob should not claim otherwise.
5. If the user provides a raw E.164 number, that number should be used directly.
6. If the user provides a contact name such as `Glennel`, Bob may pass it through and let the daemon resolve it.
7. If the user provides a bare 10-digit/11-digit North American number, Bob should normalize it to E.164 before the request is sent.
8. If the user says `call me`, Bob should resolve that through local env/address-book shortcuts before falling back to daemon contacts.
9. Bob should not ask for the operator's number again when the user says `call me` and the local shortcut data exists.
10. If the request is ambiguous, such as `call buddy`, Bob should clarify whether `buddy` is the caller persona or the callee.
11. If the user gives no clear purpose and the mission is not obvious from context, Bob should ask 1-2 short clarifying questions before placing the call.
12. If the user asks Bob to call about current OllamaBob work, the call should include bounded session context and earlier-work highlights instead of only a generic mission.
13. After a successful call, Bob should preserve or surface the `callSid` so status/hangup follow-ups can work.

## Operator Gotchas

### macOS File Access Prompts

- Opening files from `~/Desktop`, `~/Documents`, or similar locations may trigger a macOS privacy prompt the first time.
- If Bob says he hit a macOS file-access prompt while opening a file, approve the OS dialog and retry.
- A shell timeout during one of these opens can mean the app was blocked on the OS prompt, not that the open path itself is broken.

### Rich Presentation Toggle

- If `Rich Presentation` is off, Bob should not use `present`.
- In that state, simple file/URL open requests should fall back to shell `open` or a clear refusal.

### Jarvis Auth Contract

- The current daemon contract puts `/call/*` behind two layers:
  - `x-operator-secret`
  - `X-Jarvis-Key`
- `/health` is open and does not validate either one.
- A healthy `/health` check is not enough to prove calls will succeed.

### Local Jarvis Address Book

- Bob checks these local shortcut sources before daemon-side contact lookup:
  - `ZACK_PERSONAL_NUMBER`
  - `GLENNEL_PERSONAL_NUMBER`
  - `jarvis-address-book.local.json`
  - `~/Downloads/bobs_contacts.vcf`
- `jarvis-address-book.local.json` is gitignored.
- Use [jarvis-address-book.example.json](/Users/zack/ollamaBob/jarvis-address-book.example.json) as the template.
- VCF aliases come from full name, nickname, organization, and unique given name. Preferred/mobile phone numbers win when multiple phone numbers exist.

### Jarvis Live Feature Surface

Live in OllamaBob today:

- `phone_call`
- `phone_hangup`
- `phone_status`

Live in the Jarvis daemon but not yet exposed as first-class OllamaBob tools:

- call list
- mid-call message injection
- supervision
- approval queues
- contacts APIs
- follow-up APIs
- memory search

### Uncensored Mode Prerequisite

- The default uncensored tag is:

```bash
ollama pull huihui_ai/qwen3-abliterated:8b
```

## Useful Verification Commands

Run from `OllamaBob/`:

```bash
swift test
swift build
./build.sh --run
```

Check installed models:

```bash
ollama list
```
