#!/bin/bash
# Investigation A: num_ctx ceiling for gemma4:e4b and qwen3:14b on M1/32GB
#
# For each (model, num_ctx) combination, measure:
#   - first-token latency (total_duration - load_duration)
#   - total RSS of the `ollama` runner process after the request lands
#   - whether the request completes cleanly
#
# Pass criteria (per V2 plan):
#   - first-token latency < 4000ms
#   - peak RSS < 22GB (single model resident)
#   - request completes without error
#
# The minimum bar is num_ctx=16384 on gemma4:e4b.

set -u

OLLAMA_HOST="http://localhost:11434"
RESULTS="/Users/zack/ollamaBob/phase0/invA_results.jsonl"
: > "$RESULTS"

# A 6K-token fixture conversation: one long user message + one long tool result
# so the context actually matters (not just measuring empty-prompt latency).
FIXTURE_USER=$(python3 -c '
import json
blob = "The following is a list of filesystem entries Bob may need to consider when answering the next question. " + (" one two three four five six seven eight nine ten" * 500)
print(json.dumps({
  "text": blob + " Now: summarize how many entries there were in one sentence.",
}))
')

run_once () {
  local model="$1"
  local ctx="$2"
  local label="$3"

  # Warm the model by pulling once with a tiny prompt (so first-token measurement isn't load-time).
  curl -s -X POST "$OLLAMA_HOST/api/chat" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "import json; print(json.dumps({'model':'$model','stream':False,'keep_alive':'5m','messages':[{'role':'user','content':'hi'}],'options':{'num_ctx':$ctx}}))")" \
    > /dev/null 2>&1

  # Grab RSS of the runner right before the real request
  local rss_before=$(ps -o rss= -ax -p "$(pgrep -f "ollama runner" | head -1)" 2>/dev/null | tr -d ' ')
  rss_before=${rss_before:-0}

  # The real request: big prompt, measure latency
  local payload
  payload=$(python3 -c "
import json
fixture = $FIXTURE_USER
print(json.dumps({
  'model': '$model',
  'stream': False,
  'keep_alive': '5m',
  'messages': [
    {'role': 'user', 'content': fixture['text']},
  ],
  'options': {'num_ctx': $ctx, 'temperature': 0, 'num_predict': 64},
}))
")

  local t0=$(date +%s%3N)
  local response
  response=$(curl -s -X POST "$OLLAMA_HOST/api/chat" \
    -H "Content-Type: application/json" \
    --max-time 120 \
    -d "$payload")
  local t1=$(date +%s%3N)
  local wall_ms=$(( t1 - t0 ))

  local rss_after=$(ps -o rss= -ax -p "$(pgrep -f "ollama runner" | head -1)" 2>/dev/null | tr -d ' ')
  rss_after=${rss_after:-0}

  # Extract ollama's own timing from the response
  local ok="true"
  local eval_duration_ms load_duration_ms total_duration_ms error_text
  eval_duration_ms=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('eval_duration',0)//1_000_000)" 2>/dev/null || echo "0")
  load_duration_ms=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('load_duration',0)//1_000_000)" 2>/dev/null || echo "0")
  total_duration_ms=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('total_duration',0)//1_000_000)" 2>/dev/null || echo "0")
  error_text=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error',''))" 2>/dev/null || echo "")

  if [ -n "$error_text" ] || [ "$total_duration_ms" = "0" ]; then
    ok="false"
  fi

  # RSS in KB -> GB
  local rss_gb=$(python3 -c "print(round($rss_after/1024/1024, 2))")

  python3 -c "
import json
print(json.dumps({
  'label': '$label',
  'model': '$model',
  'num_ctx': $ctx,
  'ok': $ok,
  'wall_ms': $wall_ms,
  'total_duration_ms': $total_duration_ms,
  'load_duration_ms': $load_duration_ms,
  'eval_duration_ms': $eval_duration_ms,
  'rss_before_kb': $rss_before,
  'rss_after_kb': $rss_after,
  'rss_after_gb': $rss_gb,
  'error': '$error_text',
}))
" | tee -a "$RESULTS"
}

echo "=== Investigation A: num_ctx ceiling ==="
echo "Results -> $RESULTS"
echo

for model in gemma4:e4b qwen3:14b; do
  # Unload any currently-resident models between model switches by forcing keep_alive=0
  curl -s -X POST "$OLLAMA_HOST/api/chat" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$model\",\"stream\":false,\"keep_alive\":0,\"messages\":[{\"role\":\"user\",\"content\":\"ok\"}]}" \
    > /dev/null 2>&1
  sleep 2

  for ctx in 8192 12288 16384 24576 32768; do
    echo ">>> $model ctx=$ctx"
    run_once "$model" "$ctx" "main"
    # Small pause so subsequent RSS reads reflect steady state
    sleep 1
  done

  # Unload after we're done with this model so the next one starts clean
  curl -s -X POST "$OLLAMA_HOST/api/chat" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$model\",\"stream\":false,\"keep_alive\":0,\"messages\":[{\"role\":\"user\",\"content\":\"ok\"}]}" \
    > /dev/null 2>&1
  sleep 3
done

echo
echo "Done. Results in $RESULTS"
