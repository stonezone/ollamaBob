# Jarvis Phone Integration — Implementation Plan

Bob gains the ability to place real phone calls by driving the `jarvis-phone-service` daemon (`~/jarvis-phone-service`, Express on `localhost:3100`) over plain HTTP, using the same direct-HTTP pattern Bob already uses for Ollama.

**Non-negotiable constraints** (from `CLAUDE.md`):
- Direct HTTP only — **no MCP client**, no Python subprocess, no external agent runtime.
- Flat, single-level tool parameter schemas.
- All side-effectful calls go through `ApprovalPolicy` → modal NSAlert. No auto-approve, ever.
- Per-tool timeout 30s, agent loop timeout 120s, stdout/stderr truncation limits.

**Out of scope for both versions:** voice cloning, persona editor UI, daemon deployment automation, App Store distribution.

---

## V1 — Fire-and-Forget Calls (1 evening)

**Goal:** Bob can say "call Verizon for me" → modal approval → daemon places the call → Bob reports the `callSid` and subsequent status polls. No mid-call control.

### Phase 1 — Daemon-side auth gate

Today the Express `apiRouter` on `localhost:3100` is effectively open to anything that can reach the loopback port. That's fine for a browser UI behind an operator cookie, but Bob needs its own credential so it can be revoked independently.

1. Add a shared-secret middleware to `jarvis-phone-service/src/api-routes.ts`:
   - Read `process.env.JARVIS_API_KEY` at startup.
   - Gate every `/call/*` and `/calls/*` route on `X-Jarvis-Key` matching the env value.
   - Return `401 { error: "unauthorized" }` on miss.
   - **Do not** gate `/health` — Bob's preflight needs to reach it.
2. Append `JARVIS_API_KEY=<random 32-byte hex>` to `~/jarvis-phone-service/.env` and to `.env.example` (value placeholder only).
3. Restart the daemon (`npm run build && npm start`) and confirm `curl /calls/active` returns 401 without the header.

**Gate:** daemon rejects unauthenticated calls, still accepts authenticated ones, browser operator UI still works.

### Phase 2 — Bob-side settings surface

1. `AppConfig.swift`: add `jarvisBaseURL = "http://127.0.0.1:3100"` as a default constant.
2. `AppSettings.swift`: add two `@Published` + `@AppStorage` properties:
   - `jarvisPhoneEnabled: Bool` (default `false`)
   - `jarvisAPIKey: String` (default `""`, stored in `UserDefaults` — matches existing Brave key handling; acceptable since the key is local-only and the daemon is localhost-only)
3. Preferences UI (`PreferencesView.swift`): add a "Jarvis phone service" section with:
   - Enable toggle
   - API key field (secure text field)
   - "Test connection" button that `GET`s `/health` and shows the daemon version inline
4. Preflight (`PreflightChecks.swift` or wherever the existing Brave-key check lives): if `jarvisPhoneEnabled && jarvisAPIKey.isEmpty`, show a non-fatal warning badge. Do not block app launch.

**Gate:** Preferences → Test connection returns a green checkmark when the daemon is up.

### Phase 3 — `PhoneTool.swift`

Create `OllamaBob/Tools/PhoneTool.swift` following the `WebSearchTool` pattern (enum-namespaced, `static func execute(...) async -> ToolResult`).

Three tool entry points, all **flat** schemas:

```
phone_call
  persona:   string  (required, e.g. "jarvis", "bob")
  to:        string  (required — address-book name or E.164)
  purpose:   string  (required — the brief for the persona)
  max_minutes: int   (optional, default 10)

phone_hangup
  call_id:   string  (required — the callSid returned by phone_call)

phone_status
  call_id:   string  (required)
```

Implementation notes:
- One shared `JarvisClient` helper (tiny wrapper around `URLSession` + the `X-Jarvis-Key` header) so all three tools route through the same auth path.
- Each function: build request → 10s timeout on the `URLSession` configuration (well under the 30s per-tool cap) → decode into a small `Codable` struct → render a short, human-readable summary into `ToolResult.content`.
- Truncate the daemon's JSON response to `OutputLimits.shellStdoutMax` (10,000 chars). Not expected to hit it, but follow the house rule.
- Errors: HTTP non-2xx → `ToolResult(content: "Jarvis error: \(status) \(body-first-500-chars)")`. Network error → `ToolResult(content: "Jarvis unreachable at \(baseURL)")`.
- Do **not** leak the API key into any log or `ToolResult.content`.

### Phase 4 — Tool registry + catalog

1. `ToolRegistry.swift`: add three `case` entries mapping the tool names to `PhoneTool` functions. Gate on `AppSettings.shared.jarvisPhoneEnabled` — if disabled, the three tools are simply absent from the registry for that session, same way `web_search` disappears when no Brave key is configured.
2. `Resources/ToolCatalog.json`: add three entries with `category: "phone"`, `tier: 2`, short descriptions, and examples. Tier 2 so they only appear in the prompt cheat sheet when the budget allows — keeps Gemma's default view clean.
3. `BuiltinToolsCatalog.swift`: add the three tools to the built-in set so they show up in Preferences above the external CLI list.

### Phase 5 — Approval policy

`Agent/ApprovalPolicy.swift` — add three cases:

```swift
case "phone_call":
    return .modal      // real-world side effect, always requires user approval
case "phone_hangup":
    return .none       // safety action — let it run silently
case "phone_status":
    return .none       // read-only
```

Modal alert text should lead with **"Bob wants to place a phone call to \(to) as \(persona)."** followed by the purpose string, truncated to ~200 chars. The approval dialog must display the resolved number when the target is an address-book name — consider a `/contacts/lookup/:name` preflight before presenting the alert (deferred to V2 if the daemon doesn't already expose it; for V1, show the raw name).

### Phase 6 — Personality + prompt cheat sheet

1. `Personality/BobPersonality.swift`: add one line to the operating rules — "If the user asks you to make a phone call, use `phone_call`. Always include a clear purpose. Confirm the destination before calling when the user is ambiguous."
2. No new persona needed. The persona argument is passed through to the daemon, which owns persona voicing.

### Phase 7 — Acceptance tests (manual)

Walk through each scenario with the daemon running:

| # | Test | Expected |
|---|------|----------|
| P1 | "What can you tell me about Jarvis?" (daemon off) | Bob answers without the phone tool available; no error |
| P2 | Enable Jarvis in Preferences, no key set | Warning badge, tool still absent from registry |
| P3 | Configure key, Test connection | Green check, daemon version shown |
| P4 | "Call Glennel and tell him the pickup is at 5" | Modal with destination + purpose → approve → `callSid` returned → follow-up status poll works |
| P5 | Same request → deny | Daemon not contacted, Bob is told "not allowed" |
| P6 | After P4, "hang that call up" | `phone_hangup` runs silently, daemon confirms ended |
| P7 | Daemon offline | `phone_status` returns "Jarvis unreachable", Bob explains the daemon isn't running |
| P8 | Malformed API key | 401 from daemon, Bob surfaces "unauthorized" without leaking the key |

**V1 ships when all 8 pass.** Commit everything in one bundled commit per the user's workflow preference.

---

## V2 — Supervised Calls (1–2 evenings, after V1 settles)

**Goal:** Bob can watch an in-progress call, inject lines as the user dictates, and handle mid-call approvals. This is where the daemon's `/call/:id/supervise`, `/call/:id/message`, and `/call/:id/approval/*` routes earn their keep.

### Phase 8 — Expose supervise + message endpoints

Add two new tools following the same pattern:

```
phone_say
  call_id:   string
  text:      string

phone_supervise
  call_id:   string
  mode:      string   ("listen" | "takeover" | "coach")
```

Both are `.modal` approval — injecting speech into a live call is a real-world side effect, and takeover mode especially needs a human in the loop.

### Phase 9 — Live status streaming

The daemon keeps a call transcript in memory and exposes it via `/calls/active`. V2 should poll it so Bob can narrate the call back to the user:

1. New controller `JarvisCallController.swift` (`@MainActor`, `ObservableObject`). When Bob initiates a call successfully, spin up a 2s polling timer against `/call/status/:id`. Stop polling when status flips to `completed` or `failed`.
2. Surface the live transcript as a special artifact chip in the chat bubble — tap to open a side panel. Reuse the existing `ArtifactChip` pipeline; artifact kind: `phone_call_transcript`.
3. Stop the timer and close the artifact when the call ends. Final cost + duration show up in the transcript artifact footer.

### Phase 10 — Approval-request handling

The daemon can ask for mid-call approvals (e.g. "the caller is asking for the credit card number — approve?"). Wire that to NSAlert:

1. `JarvisCallController` polls `/call/:id/approval/request` or, better, exposes a long-poll endpoint on the daemon if one gets added.
2. On approval request, fire the existing `ApprovalAlert` pipeline with the daemon's question text.
3. POST the answer back to `/call/:id/approval/:approvalId`.

### Phase 11 — Personas catalog

Add a one-time preflight call to the daemon to fetch the persona list so Bob can enumerate them accurately (rather than hardcoding names). Requires a small daemon addition (`GET /personas` returning names + descriptions) — treat that as a V2 dependency on the jarvis side.

### Phase 12 — V2 acceptance tests

| # | Test | Expected |
|---|------|----------|
| P9  | Initiate a call, watch the transcript artifact populate live | Updates every 2s, stops when call ends |
| P10 | "Tell them the package is on the porch" mid-call | `phone_say` modal → approve → line injected → appears in transcript |
| P11 | Daemon raises an approval request mid-call | NSAlert pops, answer flows back, call resumes |
| P12 | Hang up mid-call | Transcript artifact finalizes with duration + cost |
| P13 | Network hiccup during polling | Retries with backoff, surfaces "lost contact" banner, resumes when reachable |

---

## Risks & open questions

- **Daemon process lifecycle.** If the daemon isn't running when Bob tries a call, failure mode should be a clear Bob explanation, not a hang. Preflight's responsibility, covered by Phase 2 + P7.
- **Key handling.** `UserDefaults` is acceptable for V1 parity with the Brave key. V2 could graduate both to Keychain in one sweep — treat as a separate small refactor, not part of this plan.
- **Address-book ambiguity.** V1 passes raw names through and lets the daemon resolve. If the daemon returns "ambiguous contact", Bob surfaces that and asks the user to disambiguate before retrying. No address-book UI in Bob.
- **Concurrent calls.** Daemon enforces `maxConcurrentCalls`. Bob should surface the 429 cleanly.
- **Uncensored mode.** Phone calls should probably be **forbidden** when the conversation is in uncensored mode — a voice going out over Twilio under an uncensored persona is a liability the sandboxed text chat doesn't share. Add a hard check in `PhoneTool.execute`: if `session.uncensoredMode`, return `ToolResult(content: "Phone calls are disabled in uncensored mode")` without hitting the daemon. Decide before Phase 5 lands.
- **Recording / consent.** Out of scope for this plan. The daemon owns recording policy; don't surface any toggle from Bob.

---

## File-by-file touch list (V1)

**New:**
- `OllamaBob/Tools/PhoneTool.swift`

**Modified:**
- `OllamaBob/AppConfig.swift`
- `OllamaBob/AppSettings.swift`
- `OllamaBob/Views/PreferencesView.swift`
- `OllamaBob/Agent/ToolRegistry.swift`
- `OllamaBob/Agent/ApprovalPolicy.swift`
- `OllamaBob/Personality/BobPersonality.swift`
- `OllamaBob/Resources/ToolCatalog.json`
- `OllamaBob/Tools/BuiltinToolsCatalog.swift`

**Daemon side:**
- `jarvis-phone-service/src/api-routes.ts` (auth middleware)
- `jarvis-phone-service/.env` + `.env.example`

Target: one bundled commit after P1–P8 pass live on the Mac.
