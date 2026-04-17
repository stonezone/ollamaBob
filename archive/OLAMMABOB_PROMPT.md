<kickoff_prompt version=”1.1”>

You are the lead implementation agent for OllamaBob v1.
Your job is to deliver a working native macOS menu bar assistant exactly as specified in the attached implementation plan (V1.1).
Move fast, but do not guess.
Use parallel sub-agents aggressively when your environment supports them.
Keep the main thread focused on integration, sequencing, validation, and quality control.

CRITICAL: Read CLAUDE.md in the project root FIRST. It contains authoritative rules, corrections, and guardrails that override any stale references in this prompt or older plan documents.


  <mission>
    Build OllamaBob v1 as a native Swift macOS app that:
    - lives in the menu bar with no Dock presence
    - shows a floating avatar window
    - opens a chat panel
    - talks directly to Ollama over HTTP using the NATIVE /api/chat endpoint (NOT /v1/chat/completions)
    - owns the agent loop in Swift (no external agent runtime)
    - supports exactly 4 tools in v1: shell, read_file, search_files, web_search
    - uses native NSAlert approvals for risky shell actions (no auto-approve, ever)
    - enforces hard output limits (10K chars shell, 100KB file, 5 search results, 30s timeout, 10 iteration max)
    - enforces a path policy (allowed/sensitive/forbidden zones)
    - persists conversations and tool logs in SQLite via GRDB
    - shows tool activity history
    - performs a full startup preflight (Ollama, model, Brave key, database, sandbox check)
    - falls back to qwen2.5:14b after 3 consecutive tool parse failures
  </mission>


<top_level_rules>
Do not replace the architecture with Hermes, Open Interpreter, MCP, Python, Electron, Docker, Node, LangChain, or a subprocess bridge.
Do not add features that were explicitly deferred to v2 or v3.
Do not add write_file in the first implementation pass.
Do not use streaming in v1.
Do not use nested tool parameter schemas.
Do not weaken approval behavior to save time. No auto-approve. All writes require explicit modal approval.
Do not silently change the model/provider/API shape without documenting the reason.
Do not use /v1/chat/completions — use /api/chat (native Ollama endpoint). This is a V1.1 correction.
Do not assume arguments are always objects — handle both object and string formats (multi-turn Ollama bug).
Do not skip the pre-kickoff checklist (capture real JSON samples before coding Codable models).
Preserve the implementation plan (V1.1) unless a blocker is proven with direct evidence.
When uncertain, inspect the real local contract first, then code against that exact contract.
Every completed code change must be validated before moving on.
Read CLAUDE.md for the latest corrections and guardrails — it overrides this prompt where they conflict.
</top_level_rules>

<execution_style>
Be implementation-first, not discussion-first.
Spawn many small specialized sub-agents in parallel for bounded tasks.
The lead agent owns the plan, integration, code review, and final correctness.
Sub-agents must not make architectural decisions. They gather facts, implement scoped slices, or test assumptions.
Prefer short feedback cycles: inspect, code, test, integrate.
Keep a running task board inside the session with status: todo, in_progress, blocked, done.
</execution_style>

<required_workflow>

Read the full attached implementation plan before coding.
Extract non-negotiable constraints into a checklist.
Verify local prerequisites before writing production code:
- macOS app target exists
- SwiftUI lifecycle available
- App Sandbox can be disabled
- Ollama reachable locally
- target model installed or installable
- Brave API key handling strategy decided
- GRDB can be added via SPM

Capture real sample JSON from the local Ollama endpoint for:
- plain response
- one tool call
- tool result follow-up
- malformed or unexpected response if encountered

Freeze Codable models only after real contract inspection.


<phase name="1_core_before_ui">
  <step>Build the core runtime before UI polish.</step>
  <step>Implement and validate, in this order:
    1. OllamaClient
    2. tool schemas
    3. ShellTool
    4. FileReadTool
    5. FileSearchTool
    6. WebSearchTool
    7. ApprovalPolicy
    8. AgentLoop
  </step>
  <step>Prove the full agent loop with real Ollama before spending effort on avatar/window polish.</step>
</phase>

<phase name="2_ui_shell">
  <step>Implement the minimum functional UI:
    - MenuBarExtra
    - chat window
    - approval dialog
    - tool activity view
    - floating avatar window
  </step>
  <step>UI must be operational, not elaborate.</step>
</phase>

<phase name="3_persistence">
  <step>Add GRDB, schema, migrations, conversation storage, and tool logging.</step>
  <step>Prove quit/reopen persistence.</step>
</phase>

<phase name="4_hardening">
  <step>Add launch health checks.</step>
  <step>Add output truncation limits, timeouts, loop caps, and safe fallback behavior.</step>
  <step>Run end-to-end acceptance tests.</step>
</phase>

</required_workflow>

<subagent_strategy>

If the environment supports subagents, use them heavily for parallelizable workstreams.
The lead agent must keep the main context clean by delegating deep dives and implementation slices outward.
Subagents should return concise results, diffs, tests, and blockers.


<parallel_subagents>
  <subagent name="contract_inspector">
    <purpose>Inspect the local Ollama /api/chat endpoint (native, NOT /v1/chat/completions) and produce exact request/response JSON samples for tool-calling flows. Save samples to samples/ directory.</purpose>
    <deliverables>
      <item>plain_response.json — no tool call</item>
      <item>tool_call_response.json — single tool call with arguments as object</item>
      <item>multi_turn_response.json — tool result fed back, second response</item>
      <item>malformed_response.json — any unexpected format encountered</item>
      <item>field-by-field contract notes (especially: arguments object vs string, tool_name vs tool_call_id)</item>
      <item>Swift Codable risk notes (especially: JSONValue enum for flexible argument parsing)</item>
    </deliverables>
  </subagent>

  <subagent name="model_reliability_tester">
    <purpose>Test Gemma 4 E4B tool-calling reliability on the exact 4 flat tools, then test Qwen fallback only if needed.</purpose>
    <deliverables>
      <item>pass/fail recommendation for default model</item>
      <item>example failures</item>
      <item>prompt/tool schema adjustments if required</item>
    </deliverables>
  </subagent>

  <subagent name="swift_project_bootstrapper">
    <purpose>Create or validate the Xcode project structure, target settings, plist behavior, and SPM dependency setup.</purpose>
    <deliverables>
      <item>project skeleton</item>
      <item>required build settings</item>
      <item>dependency wiring</item>
    </deliverables>
  </subagent>

  <subagent name="ollama_client_builder">
    <purpose>Implement OllamaClient.swift against the frozen local contract from /api/chat. Must handle: arguments as both object and string (JSONValue enum), tool results with tool_name field, options.num_ctx passthrough, and model fallback config.</purpose>
    <deliverables>
      <item>HTTP client targeting /api/chat</item>
      <item>Codable models including JSONValue for flexible argument parsing</item>
      <item>error handling (connection refused, timeout, malformed JSON)</item>
      <item>tests against saved sample JSON files</item>
    </deliverables>
  </subagent>

  <subagent name="tool_runtime_builder">
    <purpose>Implement the 4 v1 tools with hard output limits, timeouts, and safe output handling. Limits: shell 10K chars stdout / 2K stderr, file read 100KB, search 5 results / 200 chars per snippet, 30s per-tool timeout. WebSearchTool behind SearchProvider protocol.</purpose>
    <deliverables>
      <item>ShellTool.swift (Process wrapper, /bin/zsh -c, 30s timeout, output caps)</item>
      <item>FileReadTool.swift (FileManager, 100KB guard, truncation)</item>
      <item>FileSearchTool.swift (mdfind/find, max 20 results)</item>
      <item>WebSearchTool.swift (BraveSearchProvider behind SearchProvider protocol, graceful degradation if no API key)</item>
      <item>OutputLimits.swift (truncation helper with format)</item>
      <item>tool tests including: timeout, oversized output, missing file, no API key</item>
    </deliverables>
  </subagent>

  <subagent name="approval_guardrail_builder">
    <purpose>Implement ApprovalPolicy, PathPolicy, and native approval UI wiring. No auto-approve tier — only none/modal/forbidden. Path zones: allowed (~/,/tmp), sensitive (/System,/Library), forbidden (/dev,/Volumes).</purpose>
    <deliverables>
      <item>ApprovalPolicy.swift — command + path analysis</item>
      <item>PathPolicy.swift — allowed/sensitive/forbidden zones</item>
      <item>forbidden command behavior (model told "not allowed")</item>
      <item>NSAlert integration (approve/deny only, no auto-approve timer)</item>
      <item>tests for: destructive commands, write commands, forbidden commands, path-based escalation</item>
    </deliverables>
  </subagent>

  <subagent name="agent_loop_builder">
    <purpose>Implement AgentLoop.swift with bounded iteration, tool dispatch, denial handling, and final-response synthesis.</purpose>
    <deliverables>
      <item>agent loop</item>
      <item>max-iteration guard</item>
      <item>tool-call execution chain</item>
      <item>end-to-end tests</item>
    </deliverables>
  </subagent>

  <subagent name="persistence_builder">
    <purpose>Implement GRDB schema, migrations, stores, and persistence behavior.</purpose>
    <deliverables>
      <item>Schema.swift</item>
      <item>Database.swift</item>
      <item>message storage</item>
      <item>tool log storage</item>
      <item>persistence tests</item>
    </deliverables>
  </subagent>

  <subagent name="ui_builder">
    <purpose>Implement the minimum viable SwiftUI/AppKit UI shell.</purpose>
    <deliverables>
      <item>MenuBarExtra</item>
      <item>ChatPanel</item>
      <item>ChatBubble</item>
      <item>ToolActivityView</item>
      <item>AvatarWindow</item>
    </deliverables>
  </subagent>

  <subagent name="healthcheck_builder">
    <purpose>Implement full startup preflight: Ollama reachable (GET /api/tags), selected model installed, Brave API key present (optional), database writable, sandbox disabled. Show PreflightErrorView with actionable remediation if any critical check fails.</purpose>
    <deliverables>
      <item>Preflight.swift — async checks returning Status struct</item>
      <item>PreflightErrorView.swift — user-facing failure states</item>
      <item>clear remediation messages ("Start Ollama and relaunch", "Run: ollama pull gemma4:e4b")</item>
      <item>graceful degradation: missing Brave key disables web_search but doesn't block app</item>
    </deliverables>
  </subagent>

  <subagent name="qa_breaker">
    <purpose>Try to break the implementation with malformed tool calls, giant outputs, denied approvals, missing Ollama, missing Brave key, and permission failures.</purpose>
    <deliverables>
      <item>bug list</item>
      <item>repro steps</item>
      <item>severity ranking</item>
    </deliverables>
  </subagent>
</parallel_subagents>

</subagent_strategy>

<lead_agent_responsibilities>
Own the task board and keep all subagents scoped.
Merge only validated work.
Reject speculative code built against guessed API contracts.
Enforce architectural boundaries.
Continuously compare implementation against the attached plan.
Require tests or direct runtime proof for each major component before marking done.
Keep the codebase simple enough for a weekend prototype.
</lead_agent_responsibilities>

<enforcement_checks>
Fail the task if any deferred feature is added without explicit necessity.
Fail the task if MCP, Hermes, Python subprocesses, or Electron are introduced.
Fail the task if write_file is introduced before the rest of the system is proven and explicitly approved.
Fail the task if streaming is enabled in v1.
Fail the task if tool schemas become nested or complex without a proven need.
Fail the task if approval flows allow silent risky writes or auto-approve timers.
Fail the task if shell execution has no timeout or output cap.
Fail the task if the app assumes Ollama is running without a startup preflight check.
Fail the task if /v1/chat/completions is used instead of /api/chat.
Fail the task if Codable models don't handle arguments as both object AND string (multi-turn bug).
Fail the task if tool results use tool_call_id instead of tool_name (wrong endpoint format).
Fail the task if the agent loop has no max iteration cap (must be 10).
Fail the task if path policy is not enforced (allowed/sensitive/forbidden zones).
Fail the task if any acceptance test (A1-A10) is not verified before declaring done.
</enforcement_checks>

  <guardrails>
    <tool_limits>
      <item>Shell commands must have a timeout.</item>
      <item>Shell stdout/stderr must be truncated to a sane limit before feeding back to the model.</item>
      <item>File reads must have a hard size cap.</item>
      <item>Web search results must be capped and normalized.</item>
      <item>Agent loop must have a hard max-iteration limit.</item>
      <item>Malformed tool-call arguments must not crash the app.</item>
    </tool_limits>


<safety_policy>
  <item>Forbidden commands must never run.</item>
  <item>All write-like shell actions require explicit approval.</item>
  <item>No auto-approve timer for risky actions.</item>
  <item>If a tool call references a tool not in the registry, reject it and tell the model the tool is unavailable.</item>
  <item>If the model emits invalid JSON arguments, attempt one safe repair pass; otherwise return a structured tool error to the model.</item>
  <item>If Ollama is unavailable, fail gracefully and show the user how to fix it.</item>
</safety_policy>

<scope_guardrails>
  <item>No multi-conversation UI complexity in v1 beyond what is needed to persist and reload the current conversation.</item>
  <item>No browser automation, voice, screenshots, scheduling, or plugin system in v1.</item>
  <item>No App Store distribution work in v1.</item>
  <item>No premature abstraction layers beyond what the current 4-tool architecture needs.</item>
</scope_guardrails>

  </guardrails>


<implementation_details_to_respect>
Use Ollama native /api/chat endpoint (NOT /v1/chat/completions). This gives:
  - arguments as JSON objects (not strings)
  - direct num_ctx control via options field
  - tool results use tool_name field (not tool_call_id)
Use stream=false for v1.
Pass options.num_ctx=8192 in every request.
Keep the 4-tool set exactly: shell, read_file, search_files, web_search. No write_file in v1.
Use GRDB for SQLite.
Use LSUIElement=true.
App Sandbox must be OFF for local shell execution.
Keep the avatar simple and functional.
Primary model: gemma4:e4b. Fallback: qwen2.5:14b after 3 consecutive tool parse failures. Notify user on switch.
Web search uses Brave API ($5/month credit ~1000 requests). Stub behind SearchProvider protocol.
If no Brave API key, disable web_search gracefully (don't crash).
Handle the multi-turn arguments bug: Ollama may return arguments as a STRING on second tool call even if first was an object. Always normalize.
Capture real Ollama JSON samples with curl BEFORE writing Codable models. Save to samples/ directory.
</implementation_details_to_respect>

<coding_standards>
Prefer clear Swift over clever Swift.
Every public model and component should have a single clear responsibility.
Use explicit types where it improves readability.
Handle errors deliberately, not with force unwraps.
Keep files small and composable.
Add comments only where intent is not obvious.
Do not leave TODO placeholders in core paths.
Produce runnable code, not scaffolding theater.
</coding_standards>

<testing_requirements>
<unit_tests>
OllamaClient parses normal responses and tool-call responses.
ApprovalPolicy classifies representative command samples correctly.
Tool implementations handle success, failure, timeout, and truncation.
AgentLoop stops at max iterations and handles malformed tool calls safely.
Persistence can save and reload messages and tool logs.
</unit_tests>

<acceptance_tests>
  <item>User asks to list files in a directory; shell tool runs; response returns cleanly.</item>
  <item>User asks to search the web; Brave search runs; results are summarized.</item>
  <item>User asks for a destructive command; approval dialog appears; deny path works.</item>
  <item>User quits and reopens app; conversation history remains.</item>
  <item>Ollama absent at launch; user sees a clear actionable error.</item>
</acceptance_tests>

</testing_requirements>

<monitoring_and_reporting>
<lead_agent_reporting>
After each major milestone, report:
- what was completed
- what was validated
- what remains
- any blockers
- whether the architecture is still intact

Do not claim completion until the acceptance tests pass.
When a subagent returns uncertain results, verify before acting.
</lead_agent_reporting>

<required_checkpoints>
  <checkpoint name="contract_frozen">Real Ollama JSON samples captured and Codable models locked.</checkpoint>
  <checkpoint name="core_loop_proven">Agent loop completes a real tool-call round trip locally.</checkpoint>
  <checkpoint name="ui_operational">Menu bar opens chat, sends prompt, receives answer.</checkpoint>
  <checkpoint name="approvals_work">Risky shell command prompts and respects deny/allow.</checkpoint>
  <checkpoint name="persistence_working">Quit/reopen restores conversation and tool history.</checkpoint>
  <checkpoint name="launch_healthcheck_working">App detects missing Ollama and reports clearly.</checkpoint>
</required_checkpoints>

</monitoring_and_reporting>

<decision_policy>
If Gemma 4 passes the local tool-calling test, keep it.
If Gemma 4 fails the local tool-calling test repeatedly on the exact flat schemas, switch to the fallback model and continue.
If Brave API setup blocks progress, stub web_search behind a provider interface and continue building the rest.
If UI polish threatens core completion, cut polish first.
If a feature is not required for the defined acceptance tests, defer it.
</decision_policy>

<final_deliverable>
Deliver working code for OllamaBob v1 that satisfies the success criteria in the V1.1 plan.
At the end, provide:
- a concise implementation summary
- any deviations from plan with reasons
- which model was used (gemma4:e4b or fallback qwen2.5:14b) and why
- the exact remaining known issues
- how to run the app (build, prerequisites, first-launch steps)
- all 10 acceptance test results (A1-A10): pass/fail
- what should be tackled next in v2
</final_deliverable>

<v1_1_corrections>
This prompt was originally written against V1.0 of the plan. The following V1.1 corrections apply:
- API endpoint: /api/chat (native), NOT /v1/chat/completions
- Arguments format: handle BOTH object and string (multi-turn Ollama bug)
- Tool results: use tool_name field, NOT tool_call_id
- Approval: no auto-approve tier. Only none/modal/forbidden.
- Output limits: 10K chars shell, 100KB file, 5 search results, 30s timeout, 10 iterations max, 120s total
- Path policy: allowed (~/,/tmp), sensitive (/System,/Library), forbidden (/dev,/Volumes)
- Preflight: full checklist (Ollama, model, Brave key, database, sandbox)
- Model fallback: deterministic — 3 consecutive failures triggers switch, per-session scope, notify user
- Brave pricing: $5/month credit (~1000 requests), NOT free 2000/month
- Web search: behind SearchProvider protocol for future SearXNG swap
- Context size: num_ctx=8192 in options field (not via Modelfile for v1)
- CLAUDE.md in project root is the authoritative source for corrections — always read it first
</v1_1_corrections>
</kickoff_prompt>