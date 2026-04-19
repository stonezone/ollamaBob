# MULTIMEDIA_BOB — Rich Presentation for Bob's Responses

**Status:** Design (not implemented)
**Target release:** V2.10 (first release after V2.9.2 ships)
**Date:** 2026-04-19
**Author workflow:** Brainstormed + vibe_checked + peer-reviewed architecture

---

## 1. Problem

Bob's replies land as plain chat text. That's fine for "what time is it," but it's lossy for a large class of requests:

- **"Show me today's top world news headlines."** Bob produces twenty lines of titles; a rendered page with structure, links, and a readable typographic scale would be vastly clearer than a wall of chat text.
- **"Generate an image of a sunset."** A file path in chat is useless; the image should open so the user can see it.
- **"Open ~/Desktop/report.pdf for me."** Bob can't currently satisfy that verb at all.
- **"What's the page for the macOS 15 release notes?"** A URL in chat requires a manual copy/click.

Today the user has no affordance to escape the terminal-shaped transcript when the content deserves better.

## 2. Guiding Principles

1. **One primitive, many sinks.** A single `present` tool with a `kind` enum routes to the correct destination. Not four parallel tools.
2. **Bob-driven AND UI-detected — same pipeline.** Whether Bob explicitly calls `present` or the chat UI surfaces an "Open" chip for a detected artifact, both paths go through the same `PresentationService`. One code path, one set of tests, no future divergence.
3. **Never auto-launch.** Detection offers an affordance; it does not pop windows. Only Bob's explicit tool call or the user's explicit click opens anything.
4. **The kind picks the sink. No runtime decision tree.**
   - `html` → in-app `WKWebView` companion window
   - `url` → default browser via `NSWorkspace`
   - `file` → default app via `NSWorkspace`
5. **Existing policies still apply.** `present(kind=file)` routes through `PathPolicy` unchanged — Bob cannot open `/etc/passwd`. URL scheme is whitelisted to `http(s)`.
6. **Explicit-format-only detection.** To avoid privacy leaks (checking whether paths exist) and detector noise, the chat UI only surfaces chips for Markdown-formatted artifacts Bob produced intentionally — NOT any bare path in a sentence.

## 3. Architecture

```
┌──────────────────────────────┐
│ AgentLoop                    │
│  — Bob calls present(...)    │──┐
└──────────────────────────────┘  │
                                  ▼
┌──────────────────────────────┐  ┌────────────────────────────┐
│ Chat UI (detected artifact)  │  │ PresentationService        │
│  — User clicks "Open" chip   │──▶  switch kind {              │
└──────────────────────────────┘  │    html → RichHTMLState    │
                                  │    url  → NSWorkspace.open │
                                  │    file → NSWorkspace.open │
                                  │  }                          │
                                  └────────────────────────────┘
                                         │        │         │
                                         ▼        ▼         ▼
                                    In-app    Default   Default
                                    Window    browser   app (Preview,
                                              (Safari)  QuickTime, etc.)
```

Two entry points, one service, three sinks.

## 4. The `present` Tool

**Name:** `present`
**Description for Bob:** "Display rich content to the user. Use when a response is better seen than typed in chat — a rendered page, a file in its native app, or a URL in the browser."

**Parameters (flat — per project rule):**

| Field     | Type                              | Required | Meaning |
|-----------|-----------------------------------|----------|---------|
| `kind`    | enum: `html` \| `url` \| `file`   | yes      | Routes to the right sink |
| `content` | string                            | yes      | HTML source (for `html`) / URL (for `url`) / absolute path (for `file`) |
| `title`   | string                            | no       | Window title (`html`) or label used in logs |

**Approval level:** `.none` for all three kinds. PathPolicy still gates `kind=file`. Every call logged to ToolActivity.

**Error results (returned as `tool_result`, never crash):**

- `file not found` when the path doesn't exist
- `path not allowed` when PathPolicy refuses it
- `url malformed` when URL can't be parsed
- `url scheme not allowed` for non-`http(s)` URLs
- `html empty` if content is blank

## 5. Kinds → Sinks

### `html` — in-app WebView

- One shared SwiftUI `Window("Bob's View", id: "rich-html")` scene
- Observable `RichHTMLState` holds current title + HTML
- Calling `present(kind=html)` mutates state then calls `openWindow(id: "rich-html")`
- `WKWebView` configured with:
  - JavaScript disabled (`preferences.javaScriptEnabled = false`)
  - No base URL (blocks most cross-origin requests)
  - `WKNavigationDelegate` intercepts link clicks and routes to default browser instead of navigating in-frame
- `<script>` tags stripped server-side before load (belt-and-suspenders)
- Remote resources (`<img src="http…">`, `<link href="http…">`) honored by default; can be disabled by a preference

### `url` — default browser

- `NSWorkspace.shared.open(URL(string: content)!)`
- Validate scheme is `http` or `https` only. Refuse `file://`, `javascript:`, `data:`, etc.

### `file` — default app

- Expand `~` via `(path as NSString).expandingTildeInPath`
- Check file exists and passes `PathPolicy`
- `NSWorkspace.shared.open(URL(fileURLWithPath: expanded))`
- Any file type routes to its default app (Preview, QuickTime, TextEdit, etc.)
- We deliberately **do not** add MIME-type sniffing — `PathPolicy` already blocks dangerous locations, and `NSWorkspace.open` is the OS-trusted mechanism. Defense-in-depth MIME filtering can be added later if threat model evolves.

## 6. Auto-Detection (the B path)

After each assistant message renders in chat, `ChatMessageArtifactDetector` scans the plain text **only for explicitly formatted artifacts**:

| Pattern                                   | Maps to          | Why |
|-------------------------------------------|------------------|-----|
| `![alt](path)` with local file path       | `kind=file`      | Bob intentionally formatted an image |
| `[text](https?://…)` Markdown link         | `kind=url`       | Bob intentionally formatted a URL |
| Bare `https?://…` in running prose         | `kind=url`       | Low-risk — URLs are already opt-in |
| Bare file path in prose                    | **NOT DETECTED** | Avoids privacy leak from existence check; avoids noise |

Fenced code blocks are skipped. Inline `` `code` `` is skipped.

For each detected artifact, render a small chip below the assistant bubble:

- `[🔗 Open in browser]` for URL
- `[🖼 Open in Preview]` for image file
- `[📄 Open]` for generic file

Click → `PresentationService.present(kind:content:title:)` — same code path as Bob's tool call.

Detection is strictly additive. No chip = no visible change vs today.

### Why only Markdown-formatted artifacts?

The vibe_check surfaced a subtle privacy concern: scanning bare paths and checking whether they exist before showing a chip would leak "this path exists on disk" back to Bob's reasoning process (via the UI deciding to render a chip). Limiting detection to Markdown formatting means Bob's intentional output drives the affordance, not filesystem interrogation.

## 7. Files to Add / Modify

### New files

| File | Purpose |
|------|---------|
| `OllamaBob/Tools/PresentTool.swift` | Tool registration, argument parsing, error mapping |
| `OllamaBob/Services/PresentationService.swift` | The single entry point: `func present(kind:content:title:)` |
| `OllamaBob/Models/RichHTMLState.swift` | `@Published var title: String; @Published var html: String` |
| `OllamaBob/Views/RichHTMLView.swift` | `NSViewRepresentable` wrapping `WKWebView` with link-navigation delegate |
| `OllamaBob/Views/ArtifactChip.swift` | Small clickable chip view for detected artifacts |
| `OllamaBob/Views/ArtifactDetector.swift` | Pure scanning logic (regex + AST-ish skip for code blocks), fully unit-testable |

### Modified files

| File | Change |
|------|--------|
| `OllamaBob/OllamaBobApp.swift` | Register `Window("Bob's View", id: "rich-html")` scene; inject `RichHTMLState` via `@StateObject` on `AppState` |
| `OllamaBob/Agent/ToolRegistry.swift` | Register `PresentTool` behind the "enable rich presentation" preference |
| `OllamaBob/Agent/ApprovalPolicy.swift` | Classify `present` as `.none` |
| `OllamaBob/Agent/PathPolicy.swift` | No change — already handles path validation |
| `OllamaBob/Personality/BobPersonality.swift` | Add the "you have a `present` tool, use it when…" paragraph (see §8) |
| `OllamaBob/Views/ChatTranscriptView.swift` (or wherever assistant messages render) | Render `ArtifactChip`s under assistant messages |
| `OllamaBob/Views/PreferencesView.swift` | Add "Rich Presentation" section with toggles (see §10) |
| `AGENTS.md` | Document the new components |

## 8. System Prompt Addition (Bob's Instructions)

```
You can show content in rich form via the `present` tool. Use it when:
- The user asked for a list or set of items better rendered as a page
  (news, search results, tables)
- You generated or fetched a file the user should see
- You're pointing the user at a URL they should read in their browser
- A file already on disk should be opened in its default app

kind="html" with a full <html>…</html> string opens a companion window.
kind="url" opens the user's default browser.
kind="file" with an absolute path opens the default app for that file type.

Don't use it for short answers or conversational replies. When in doubt,
answer in chat and skip the tool.
```

## 9. Security & Policy

- `present(kind=url)`: scheme whitelist (`http`, `https` only)
- `present(kind=file)`: `PathPolicy` gate; existing rules cover `/System`, `/private`, `/etc`, `/dev`, `/Volumes`
- `present(kind=html)`:
  - JavaScript disabled in `WKWebView`
  - `<script>` tags stripped from HTML source before load
  - No base URL → blocks most cross-origin requests
  - Link navigation intercepted → default browser
- Approval level: `.none` (all three kinds are user-visible but not filesystem-mutating from the user's POV)
- Every `present` call logged to `ToolActivity`

**Future hardening (V2+):** investigate integrating **SwiftSoup** or a similar server-side sanitizer for more robust HTML filtering if Bob starts rendering larger chunks of untrusted content (e.g., full pages pulled from `web_search`).

## 10. Preferences

Under **Preferences → Tools → Rich Presentation**:

| Toggle                                | Default | Effect when OFF |
|---------------------------------------|---------|-----------------|
| Enable rich presentation              | ON      | `present` tool unregistered; all chips hidden |
| Allow remote resources in HTML        | ON      | Strip `<img src="http…">`, `<link>`, etc. before WebView load |
| Show artifact chips in chat           | ON      | Auto-detection disabled (Bob-initiated still works) |

## 11. Acceptance Tests

| #  | Flow |
|----|------|
| M1 | "Show me today's top world news headlines" → Bob calls `web_search`, formats HTML, calls `present(kind=html)` → companion window opens with rendered page |
| M2 | "Open the URL for the macOS 15 release notes" → Bob calls `present(kind=url)` → default browser opens to the URL |
| M3 | "Open ~/Desktop/screenshot.png" → Bob calls `present(kind=file)` → Preview opens |
| M4 | Bob replies with Markdown `![screenshot](/Users/zack/Downloads/foo.png)` → chip `[🖼 Open in Preview]` appears → click → Preview opens |
| M5 | "Open /etc/passwd" → Bob attempts `present(kind=file)` → `PathPolicy` refuses → tool returns `path not allowed` → Bob tells user |
| M6 | Preferences → disable rich presentation → Bob no longer sees `present`; chips no longer render |
| M7 | Link click inside in-app WebView opens default browser, does NOT navigate inside the WebView |
| M8 | Bob reply with bare file path `/Users/zack/file.txt` in prose → **no chip** (explicit-format rule) |
| M9 | Bob reply containing `` `code with /path/example` `` → no chip (code-span skipped) |

## 12. Design Tradeoffs Explicitly Chosen for V1

Each of these was raised during vibe_check and deliberately resolved to keep V1 lean:

- **Singleton window vs. `WindowGroup`.** V1 uses one `Window(id:"rich-html")` that replaces content on each `present(kind=html)` call. Delivers the common "show me this summary page" case; multi-window "let me compare rich views" deferred to V2 based on feedback.
- **Detector scope.** V1 detects only Markdown-formatted artifacts. Bare paths are ignored. Cheaper on noise, zero privacy leak, easy to expand later if we learn users want bare-path detection.
- **Aesthetic consistency.** A titled window popping up from a chromeless menu-bar app is a mild break in aesthetic. Accepted for V1. Future idea: position the window near the menu-bar icon on first open, or use a borderless window styled to match Bob's bubble aesthetic. Not a V1 blocker.
- **No MIME-type sniffing on `kind=file`.** `PathPolicy` already blocks dangerous locations; `NSWorkspace.open` is the OS-trusted pathway. Defense-in-depth MIME filtering can be added in V2 if needed.
- **HTML sanitization is rudimentary.** `<script>` strip + JS-disabled WebView + no base URL covers the common threat model. SwiftSoup (or similar) for stricter sanitization is a V2 candidate.
- **Bob-initiated AND UI-detected converge on one service.** Non-negotiable core of the design — this is what makes it "smarter A+B."

## 13. Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Bob spams `present` on every reply | System prompt discourages; ToolActivity logging makes it visible; user can disable the tool via Preferences |
| WebView with JS disabled breaks Bob's HTML layouts | Bob generates his own HTML — CSS-only layouts work fine; no JS needed for rendering news headlines/tables |
| `LSUIElement=true` app + `NSWorkspace.open(url)` | Confirmed working pattern — user's browser activates, Bob stays menu-bar-only |
| Singleton HTML window replaces a view the user was still reading | V1 acceptable; V2 consideration |
| Aesthetic mismatch — titled window vs. chromeless avatar | Accepted tradeoff. Future: anchor position, or borderless style. |
| Detector regex false positives (e.g., link inside sentence is conversational, not a call to action) | Low cost — chip is unobtrusive, user ignores. If it proves noisy, tighten by requiring Markdown link syntax for URLs too. |

## 14. Out of Scope for V1

Explicitly deferred to V2+:

- Multiple simultaneous rich-HTML windows
- Native `markdown` kind (Bob can emit HTML directly for now)
- Native in-app image/video/audio viewers (NSWorkspace handoff covers these)
- "Save artifact to disk" / "Print" controls in the rich window
- Pin/persist a rich view across new chat sessions
- SwiftSoup-based HTML sanitization
- MIME-type sniffing for `kind=file`
- Bare-path detection in chat
- Custom rich-window chrome matching Bob's aesthetic

## 15. Implementation Order

1. `Services/PresentationService.swift` — pure, no UI yet, unit tests for routing and error cases
2. `Models/RichHTMLState.swift` + `Views/RichHTMLView.swift` + new `Window` scene in `OllamaBobApp.swift`
3. `Tools/PresentTool.swift` + registry + approval policy wiring
4. Personality prompt update (`BobPersonality.swift`)
5. `Views/ArtifactDetector.swift` (unit-tested) + `Views/ArtifactChip.swift` + transcript integration
6. Preferences pane additions
7. Acceptance tests M1–M9
8. `AGENTS.md` update documenting the new components
9. Commit message: `feat: V2.10 — rich presentation (HTML window + URL/file handoff) with unified Bob-driven + UI-detected pipeline`

---

## Source

- Idea originated with the user asking, "say I asked Bob for top news headlines — how could he present that more usefully than terminal text? Launch a window like a web page? Launch Preview for images? Link him to launch the default app for whatever media is in his response?"
- Design synthesized as a **smarter A + B**: Bob's explicit `present` tool call (A) and UI-driven auto-detection of artifacts in chat (B), unified behind a single `PresentationService` so both paths share code, tests, and policy.
- Validated via `vibe_check` — raised concerns about WebView hardening scope, singleton vs. windowgroup, detector noise, aesthetic fit, file-existence privacy leak, and MIME sniffing. All resolved with explicit V1 tradeoffs documented in §12.
