# Wire Format Notes — Captured 2026-04-06

Real Ollama 0.20.2 responses from gemma4:e4b against /api/chat.

## Differences from V1.1 Plan

1. **`thinking` field** — Message includes optional `thinking` string even with `stream: false`. Must be optional in Codable.
2. **`id` on tool_calls** — Plan said "No id field on tool_calls in native /api/chat". WRONG — real response has `"id": "call_nxszzglf"`. Make it optional.
3. **`index` on function** — Real response has `"index": 0` inside function object. Not in plan. Make it optional.
4. **Arguments ARE objects** — Confirmed: `"arguments": {"command": "ls /tmp"}` is a dict, not a string. Still must handle string fallback per multi-turn bug.

## Confirmed from Plan

- `role: "assistant"` with empty `content` when tool_calls present
- `tool_name` field on tool result messages works
- `options.num_ctx` accepted in request
- `stream: false` works correctly
- `done: true` and `done_reason: "stop"` present
- Gemma 4 correctly selects the right tool from a 4-tool schema

## Fallback Model Note

qwen2.5:14b is NOT installed. qwen3:14b IS installed. Adjust fallback config.
