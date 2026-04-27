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

1. Preferences -> Tools shows the full built-in catalog. Verify expected categories: Files, Shell, Git, Web, Phone, Presentation, Media, Utility, YouTube, Clipboard, Automation, Memory.
2. `youtube_search` and `youtube_download` require `yt-dlp` on PATH. If missing, Bob returns "yt-dlp not found on PATH. Install with: brew install yt-dlp".
3. `phone_call`, `phone_hangup`, `phone_status` only appear when Jarvis phone is enabled in Preferences and both `JARVIS_API_KEY` and `OPERATOR_API_SECRET` are configured.
4. `web_search` only appears when `BRAVE_API_KEY` is configured.
5. Read-only tools (green dot) should run silently. Write/ASK tools (orange dot) should show a modal approval dialog.

### Jarvis Phone

1. Preferences -> Tools -> `Enable Jarvis phone service` is on.
2. Both secure fields are filled:
   - `Jarvis API key`
   - `Operator secret`
3. `Test connection` returns healthy reachability.
4. Ask Bob to place a call:
   - expected: approval modal for `phone_call`
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
12. After a successful call, Bob should preserve or surface the `callSid` so status/hangup follow-ups can work.

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
- `jarvis-address-book.local.json` is gitignored.
- Use [jarvis-address-book.example.json](/Users/zack/ollamaBob/jarvis-address-book.example.json) as the template.

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
