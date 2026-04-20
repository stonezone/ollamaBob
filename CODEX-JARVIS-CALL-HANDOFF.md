# Codex Jarvis Call Handoff

## Scope Completed

Implemented the `JARVIS_BOB_CALLS.md` V1 app-side slice in OllamaBob.

This pass added:
- Preferences support for the Jarvis phone daemon
- non-fatal preflight warning when Jarvis is enabled without a key
- built-in phone tools:
  - `phone_call`
  - `phone_hangup`
  - `phone_status`
- tool registry and approval policy wiring
- prompt/catalog exposure for the phone tools
- end-to-end app-side tests for the Jarvis V1 contract

Daemon-side auth gating was already present in `/Users/zack/jarvis-phone-service` and was not changed in this pass.

## Files Changed

App/runtime:
- [OllamaBob/OllamaBob/AppConfig.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/AppConfig.swift)
- [OllamaBob/OllamaBob/Models/AppSettings.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Models/AppSettings.swift)
- [OllamaBob/OllamaBob/Views/PreferencesView.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Views/PreferencesView.swift)
- [OllamaBob/OllamaBob/Agent/Preflight.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Agent/Preflight.swift)
- [OllamaBob/OllamaBob/Views/PreflightErrorView.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Views/PreflightErrorView.swift)
- [OllamaBob/OllamaBob/Tools/PhoneTool.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Tools/PhoneTool.swift)
- [OllamaBob/OllamaBob/Agent/AgentLoop.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Agent/AgentLoop.swift)
- [OllamaBob/OllamaBob/Agent/ToolRegistry.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Agent/ToolRegistry.swift)
- [OllamaBob/OllamaBob/Agent/ApprovalPolicy.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Agent/ApprovalPolicy.swift)
- [OllamaBob/OllamaBob/Personality/BobOperatingRules.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Personality/BobOperatingRules.swift)
- [OllamaBob/OllamaBob/Tools/BuiltinToolsCatalog.swift](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Tools/BuiltinToolsCatalog.swift)
- [OllamaBob/OllamaBob/Resources/ToolCatalog.json](/Users/zack/ollamaBob/OllamaBob/OllamaBob/Resources/ToolCatalog.json)

Tests:
- [OllamaBob/Tests/OllamaBobTests/JarvisPhoneV1Tests.swift](/Users/zack/ollamaBob/OllamaBob/Tests/OllamaBobTests/JarvisPhoneV1Tests.swift)

Handoff:
- [CODEX-JARVIS-CALL-HANDOFF.md](/Users/zack/ollamaBob/CODEX-JARVIS-CALL-HANDOFF.md)

## Actual App Behavior

### Settings / Preferences

New preferences section:
- `Enable Jarvis phone service`
- secure `Jarvis API key` field
- `Test connection` button against `GET http://127.0.0.1:3100/health`

Notes:
- the health check does not send `X-Jarvis-Key`
- if the daemon exposes no version field, the UI shows `Healthy`
- if Jarvis is enabled but the key is blank, preflight shows a warning but app launch is not blocked

### Tool Exposure Rules

The phone tools are only exposed when all of these are true:
- `jarvisPhoneEnabled == true`
- `jarvisAPIKey` is non-empty
- `jarvisBaseURL` parses successfully

If any of those are false:
- the phone tools are absent from `ToolRegistry`
- Bob does not advertise them in the prompt/tool list

### Tool Approval

- `phone_call` -> `.modal`
- `phone_hangup` -> `.none`
- `phone_status` -> `.none`

### Tool Execution Contract

Model-facing tool schema:
- `phone_call(persona:, to:, purpose:, max_minutes:)`
- `phone_hangup(call_id:)`
- `phone_status(call_id:)`

Daemon-facing HTTP contract actually used by the app:
- `POST /call/initiate`
- `POST /call/hangup/:id`
- `GET /call/status/:id`

The app maps the model-facing fields to the daemon payload:
- `persona` -> normalized daemon `caller`
- `purpose` -> `missionBrief`
- `max_minutes` -> `maxDurationSeconds`

Current caller normalization:
- `jarvis` -> `bob`
- `bob` -> `bob`
- `buddy` -> `buddy`
- `zack` -> `zack`
- `glennel` -> `glennel`
- `glennel_naggy` / `glennel naggy` / `naggy` -> `glennel_naggy`

Any unsupported or blank persona string now defaults locally to `bob` before network.

### Response Rendering

Success summaries:
- call start returns `callSid`, normalized persona, target, status, optional max minutes, and any daemon message
- hangup returns call id plus hangup status
- status returns call id, status, optional duration, optional cost, and any daemon message

Failure summaries:
- network/unreachable -> `Jarvis unreachable at http://127.0.0.1:3100`
- HTTP non-2xx -> `Jarvis error: <status>: <body prefix>`
- missing inputs -> local validation failure

## Verification Completed

Automated:
- `swift build` -> passed
- `swift test` -> passed

Current suite result at handoff time:
- `95` tests
- `0` failures

Important regression that was fixed during integration:
- worker output initially listed the phone tools but did not actually dispatch them in `AgentLoop.executeTool`
- worker output initially used the wrong daemon routes/body shape
- worker tests initially leaked to the live daemon; the test harness was corrected to read streamed request bodies and the phone client was aligned to the real contract
- the shell/process runner refactor briefly made shell launch failures look like successful commands with `[exit code: -1]`; `ShellTool` now restores the original failure behavior
- the external tool probe path briefly hung the full suite; `ToolRuntime` now probes sequentially until `ProcessRunner` grows a truly non-blocking implementation

## Manual QA Still Recommended

Run these with the real daemon up:

1. Enable Jarvis in Preferences, leave key blank
   - expected: warning in preflight, tools absent

2. Add the real key and click `Test connection`
   - expected: healthy state in Preferences

3. Ask Bob to place a call
   - expected: approval modal for `phone_call`
   - after approval: daemon returns a `callSid`

4. Ask Bob for call status using the returned id
   - expected: `phone_status` runs silently and returns the daemon status

5. Ask Bob to hang up the call
   - expected: `phone_hangup` runs silently and the daemon confirms the call ended

6. Disable Jarvis in Preferences
   - expected: phone tools disappear from the live tool registry

## Known Limits / Open Follow-Up

- Preferences health check only shows a version if `/health` returns one. The current daemon contract previously inspected did not expose a version field.
- Caller normalization is intentionally conservative. If the daemon adds more caller identities, update `PhoneTool.normalizeCallerLabel`.
- This pass did not implement V2 supervised-call features.
- This handoff covers the app-side Jarvis feature only. Website/docs refresh for public-facing OllamaBob pages is a separate follow-up.
