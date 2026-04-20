# Blind Peer Review v2 — Chat UI Consensus

**Date:** 2026-04-20
**Peers:** Gemini 2.5 Pro (external, balanced), Codex GPT-5.4 (external, balanced), Claude Opus (local).
**Mode:** Blind review of post-V2.10 chat rendering pipeline. No code changes made.
**Scope reviewed:** `ChatBubble.swift`, `ArtifactDetector.swift`, `ArtifactChip.swift`, `RichHTMLView.swift`, `PresentationService.swift`, `Conversation.swift`, `RichHTMLState.swift`, plus excerpts of `BobsDeskView.swift` and `ChatSessionController.swift`.

---

## Validated findings (multi-source corroboration)

### V-001 — Unbounded `blockCache` static dictionary leaks memory (HIGH)
**Confirmed by:** Gemini F-001, Codex F-002, Opus F-001, my own analysis.
**Location:** `ChatBubble.swift:16` — `private static var blockCache: [String: [Block]] = [:]`.
**Failure mode:** Menu-bar app runs for days/weeks; cache never evicts. Every unique message text retained forever. Also dirty after persona/wipe-conversation operations.
**Recommendation:** Replace with `NSCache<NSString, NSArray>` (auto-evicts under pressure) or bounded LRU. Optionally key on `(persona, message.id)` so cache lifetime tracks visible transcript window.

### V-002 — `interleavedItems` re-sorts full transcript on every body re-eval (HIGH)
**Confirmed by:** Gemini F-002, Codex F-003, Opus F-004.
**Location:** `BobsDeskView.swift:1119-1128`. Computed property merges `session.messages` + `systemNotices` and runs O(N log N) sort on every SwiftUI invalidation.
**Failure mode:** Long sessions (1000+ messages) chug on every keystroke / streaming update / panel toggle. Main-thread blocking.
**Recommendation:** Hoist to `@State var interleavedItems: [InterleavedItem]`. Recompute via `.onChange(of: session.messages.count)` and `.onChange(of: systemNotices.count)`. Since both sources are append-only chronologically, an incremental merge (insertion-sorted append) avoids the full sort entirely.

### V-003 — `conciseToolAnswer` mutates persisted assistant content (HIGH — correctness regression)
**Confirmed by:** Codex F-001, my own analysis. Gemini flagged in `open_questions`.
**Location:** `ChatSessionController.swift:316-370`.
**Failure mode:** Heuristic disk-space rewriter (`score()` favors digits + "free"/"available"/"%/used", penalizes "basically"/"usually"; `focusAnswerPhrase` truncates to "you have…" / "there are…"; force-prefixes "Sir, " on `"sir"` substring) silently rewrites the model's reply in-place before persistence. Effects:
- Non-disk replies get mangled by disk-tuned heuristics.
- Persona voice destroyed (no persona says "Sir, " unprompted).
- "sir" substring matches mid-word ("desire", "sirius").
- Database stores edited string — original model output is lost.

**Recommendation:** Delete entirely. If a "concise summary" is desired, render it transiently in the bubble view (no DB mutation), gate by tool category, and let the persona prompt handle tone. The model already produces a summary turn after every tool call.

### V-004 — Markdown image syntax forces entire bubble to monospaced raw text (MEDIUM)
**Confirmed by:** Codex F-005, my own analysis.
**Location:** `ChatBubble.swift:49-51` `shouldRenderAssistantContentLiterally` + `:264-285` `textBubble`.
**Failure mode:** A reply like `Here is a chart: ![chart](https://…)\n\n**Summary:** Sales up 12%.` renders as one giant monospaced block — bold/headings/lists lost, ArtifactChip never gets to surface the image as a tappable chip.
**Recommendation:** Don't switch the whole bubble to literal mode. Let the existing markdown segmentation in `assistantTextContent` handle it; rely on `ArtifactDetector` to extract images as chips. The "literal" path should be removed or scoped to specific known-broken inputs.

### V-005 — HTML sanitizer regex blacklist has known bypasses (MEDIUM)
**Confirmed by:** Gemini F-005 (generic concern), Opus F-002 (specific bypass classes).
**Location:** `PresentationService.swift:192-223`.
**Specific gaps Opus identified:** Slash-separator handlers (`<img/onerror=x>`), unquoted attribute values, mixed-case event names that escape strict word-boundary patterns, attribute splitting across whitespace.
**Failure mode:** Local CSP + `allowsContentJavaScript=false` is the real defense — bypass impact is limited to view corruption + unintended remote loads if remote resources are enabled.
**Recommendation:** Hardened approach without new deps: a single tag-walking pass that drops all `on*` attributes, all `javascript:` / `vbscript:` / `data:` (when not allowed) URI values, and all unknown tags from a small whitelist (`p,br,h1-h6,ul,ol,li,strong,em,code,pre,blockquote,a,img,table,thead,tbody,tr,td,th,div,span`). Don't retire the CSP — keep both.

---

## Contested findings (rejected after evidence validation)

### C-001 — Gemini F-003 "UI state updated from background thread" — **INVALID**
Gemini claimed `ChatSessionController.sendMessage`'s `Task { await … }` block mutates `@Published` properties off the main actor. Verified: `ChatSessionController.swift:3-4` declares the **entire class `@MainActor`**. An unstructured `Task` started inside a `@MainActor` method inherits the actor's executor unless explicitly detached. No threading violation.

### C-002 — Gemini F-004 "Invalid property wrapper syntax causes build failure" — **HALLUCINATED**
Gemini quoted `@OllamaBob/OllamaBob/Models/RichHTMLState.swift private var isToolPanelExpanded = false` as evidence at `ChatBubble.swift:224-225`. Actual code reads `@State private var isToolPanelExpanded = false`. The file path appears nowhere as an attribute. The project compiles; this finding is fabricated. Reduces overall trust in Gemini's review pass.

---

## Peer-only findings (single-source, evidence verified)

### P-001 — Codex F-004: Rich HTML turns cannot be reopened (MEDIUM)
`ArtifactDetector` never emits `kind: .html`; it only detects URLs / file paths / code. Once the modal closes, the rendered HTML lives only in transient `RichHTMLState` keyed by message ID; user has no chip to reopen. Two-line fix: when `present` tool call has `kind=html`, synthesize an `.html` artifact pointing at the message ID for the chip strip.

### P-002 — Codex F-006: Greeting system notice right-aligned (LOW)
`BobsDeskView.swift:1132-1146` — greeting branch emits `HStack { Spacer(); Text(notice.text); … .padding(.trailing, 8) }`. Pushes greeting to right edge while every other notice centers. Likely a copy-paste from a sender bubble layout. Remove the leading `Spacer` or wrap in centered HStack.

### P-003 — Opus F-003: `_WrappingChipFlowLayout` coordinate inconsistency (MEDIUM)
`ChatBubble.swift:484-545` — `sizeThatFits` checks `if x > 0 { wrap }` (origin-relative); `placeSubviews` checks `if x > bounds.minX { wrap }` (bounds-relative). When parent gives the layout a non-zero `bounds.minX`, the two passes disagree on row count → measured height ≠ placed height → chips clip or overflow. Pick one frame (use `bounds.minX`/`bounds.maxX` consistently, or normalize to origin in both passes).

### P-004 — Opus F-005: Per-bubble `@ObservedObject` cascade redraws (MEDIUM)
Every `ChatBubble` observes the shared session/state object. One mutation invalidates every visible bubble even though only one changed. Combined with V-001/V-002, this magnifies the perf cost. Recommend: isolate per-bubble dependencies (pass concrete value types in, observe only the slice each bubble actually reads — e.g., the message itself plus expansion state).

### P-005 — Opus F-006: `sanitizedToolContent` misnamed (LOW)
Reads as security-critical but the function does cosmetic trimming, not sanitization. Rename to `displayableToolContent` or similar to avoid future contributors assuming it's the security boundary.

### P-006 — Opus F-007: Auto-scroll observers only watch `.count` (LOW)
`onChange(of: session.messages.count)` misses content mutations to existing messages (e.g., the streaming-style append where the last message's content grows). Symptom: scroll pins at message N when message N's body keeps growing past the viewport. Add an observer on the last message's content length, or a counter that increments on any message mutation.

### P-007 — Opus F-008: WrappingChipLayout cache parameter unused (LOW)
`makeCache()`/`updateCache()` return a value that's never read. Either implement caching of measured sizes (real win on chip-heavy bubbles) or remove the parameter to reduce confusion.

### P-008 — Opus F-009: `ArtifactDetector` has no per-message caching (LOW)
Detector runs full regex+NSDataDetector pass every body re-eval. Same input → same output → memoize by message id + content hash.

### P-009 — Opus F-010: `targetFrame?.isMainFrame ?? true` (LOW)
`RichHTMLView.swift` defaults nil `targetFrame` to "is main frame" → unwanted navigations may pass through. Default to `false` (treat unknown as non-main → external open via `ExternalURLPresenter`).

### P-010 — Opus F-011: `DetectedArtifact.id` uses full content string (LOW)
`"\(kind.rawValue)|\(content)|\(title ?? "")"` — long code blocks or HTML snippets become large dictionary keys. Hash via SHA-256 prefix or use UUID generated once per detection.

### P-011 — Opus F-012: Expand/Collapse buttons missing accessibility labels (LOW)
Transcript-section toggles read as bare glyphs to VoiceOver. Add `.accessibilityLabel("Expand transcript")` / `"Collapse transcript"`.

---

## My-only findings (not raised by peers)

None novel — V-003 (`conciseToolAnswer`) was the one finding I had pre-flagged that peers had not seen until Codex independently corroborated. All other items I'd previously flagged are subsumed by validated findings.

---

## Coverage gaps

- No peer ran the app — all findings are static analysis only. UI behavior under live streaming, tool-call cascades, persona switching, and long-running sessions is not empirically verified.
- `AgentLoop.swift` was not in any peer's bundle — interaction between agent state mutations and UI render cycles unreviewed.
- Only excerpts of `BobsDeskView.swift` (1342 lines) and `ChatSessionController.swift` (371 lines) were sent — peers did not see avatar window code, voice playback timing, or persona prompt assembly.
- No VoiceOver / accessibility audit performed — Opus F-012 is the only a11y finding and it's a guess from missing labels.
- Greeting flow, first-launch onboarding, and Permissions panel all unreviewed.

---

## External exposure summary

| Peer | Mode | Bundle | Categories sent | Withheld |
|------|------|--------|-----------------|----------|
| Gemini 2.5 Pro | balanced | `/tmp/bob_chat_ui_review_v2.md` (75KB) | Source excerpts of 9 view/model files | API keys, .env, AgentLoop.swift, persistence schema |
| Codex GPT-5.4 | balanced | same bundle | same | same |
| Claude Opus | local-only | same (in-process Agent) | n/a — never left machine | n/a |

No secrets, credentials, or PII transmitted. All file content was UI-layer code already reviewable on local disk.

---

## Bottom line

**Top 3 highest-leverage fixes:**
1. **V-003 — Delete `conciseToolAnswer`.** This is a correctness regression actively corrupting persisted model output. Highest urgency despite its small code footprint.
2. **V-001 — Replace `blockCache` with `NSCache`.** Single-line change, fixes a slow-burn memory leak that will manifest as the user's first "why did Bob get sluggish after a week" complaint.
3. **V-002 — Memoize `interleavedItems` with incremental merge.** Largest perf win for long sessions; protects the main thread.

**Then in priority order:** V-004 (markdown image bubble bug), P-001 (rich HTML reopen affordance), V-005 + the unquoted-handler bypass class, P-003 (chip layout coord bug), P-004 (per-bubble observer cascade), P-006 (auto-scroll content blindness), then the rest of the LOW-severity polish.

**Cross-peer trust note:** Gemini produced one fabricated finding (C-002) and one threading false positive (C-001). Of its 5 findings, 3 were valid. Codex landed 6/6 valid. Opus landed 12/12 with verifiable line references. Weight Codex/Opus more heavily on the next pass.
