# OllamaBob Operator QA Notes

**Date:** 2026-04-20

## Core Manual Checks

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
3. `phone_call`, `phone_hangup`, `phone_status` only appear when Jarvis phone is enabled in Preferences and a `JARVIS_API_KEY` is set.
4. `web_search` only appears when `BRAVE_API_KEY` is configured.
5. Read-only tools (green dot) should run silently. Write/ASK tools (orange dot) should show a modal approval dialog.

## Operator Gotchas

### macOS File Access Prompts

- Opening files from `~/Desktop`, `~/Documents`, or similar locations may trigger a macOS privacy prompt the first time.
- If Bob says he hit a macOS file-access prompt while opening a file, approve the OS dialog and retry.
- A shell timeout during one of these opens can mean the app was blocked on the OS prompt, not that the open path itself is broken.

### Rich Presentation Toggle

- If `Rich Presentation` is off, Bob should not use `present`.
- In that state, simple file/URL open requests should fall back to shell `open` or a clear refusal.

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
